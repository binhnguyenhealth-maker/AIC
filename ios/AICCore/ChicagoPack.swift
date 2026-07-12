import Foundation
import SQLite3

public enum ChicagoPackError: Error, Equatable, LocalizedError {
    case missingPack
    case invalidDatabase(String)
    case unsupportedSchema(String)
    case outsideChicago
    case noEligibleReferences
    case insufficientCellCoverage

    public var errorDescription: String? {
        switch self {
        case .missingPack: "The Chicago data pack is not installed."
        case let .invalidDatabase(message): "The Chicago data pack could not be read: \(message)"
        case let .unsupportedSchema(version): "This data pack uses unsupported schema \(version)."
        case .outsideChicago: "Choose a point inside Chicago."
        case .noEligibleReferences: "No eligible Chicago comparison locations are available."
        case .insufficientCellCoverage: "This point is too close to the Chicago boundary for a complete 500 m comparison. Choose another nearby point."
        }
    }
}

public final class ChicagoPack {
    public static let supportedSchemaVersion = "3"
    public static let supportedMethodologyVersion = "beta-cell250-q5-area-v3"
    public static let radiusMeters = 500.0
    public static let aggregateCellSizeMeters = 250.0
    public static let aggregateBandSize = 5
    public static let scanCoordinateSnapMeters = 1.0
    public static let overlapSubcellsPerAxis = 10
    public static let overlapSubcellSizeMeters = 25.0
    public static let coverageLatticeSpacingMeters = 100.0
    public static let coverageDiskLatticeSamples = 81
    public static let referenceSpacingMeters = 500.0
    public static let gridAnchorLatitude = 41.6
    public static let gridAnchorLongitude = -87.95
    public static let earthRadiusMeters = 6_371_008.8
    public static let requiredPackPrivacy = "nonoverlapping_250m_cells_independent_q5_bands_no_exact_or_residual_total"
    public static let requiredCountSemantics = "privacy_coarsened_estimated_contributing_incidents"
    public static let requiredReferenceEligibility = "all_100m_disk_lattice_points_inside_official_city_union"
    public static let requiredNetworkPolicy = "local_only_no_coordinates_query_nodes_or_geographic_cells_uploaded"

    private var database: OpaquePointer?
    private var validatedMetadata: PackMetadata?
    private var cityBoundary: [GeoPolygon] = []
    private var preparedNeighborhoods: [PreparedNeighborhood] = []
    private let destructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private struct PackMetadata {
        let sourceThroughDate: String
        let periodStart: String
        let methodologyVersion: String
        let aggregateRowRange: ClosedRange<Int64>
        let aggregateColumnRange: ClosedRange<Int64>
        let aggregateCellCount: Int64
    }

    public init(url: URL) throws {
        var opened: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &opened, flags, nil) == SQLITE_OK else {
            let message = opened.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            if let opened { sqlite3_close(opened) }
            throw ChicagoPackError.invalidDatabase(message)
        }
        database = opened

        do {
            guard try tableExists("metadata"),
                  try tableExists("aggregate_cells"),
                  try tableExists("reference_distribution"),
                  try tableExists("neighborhood_centroids"),
                  try tableExists("neighborhoods"),
                  try tableExists("city_boundary") else {
                throw ChicagoPackError.invalidDatabase("required tables are missing")
            }
            guard try !tableExists("query_nodes"),
                  try !tableExists("incidents"),
                  try !tableExists("source_incidents") else {
                throw ChicagoPackError.invalidDatabase("the pack contains a forbidden precise or overlapping-data table")
            }
            try validateTableContracts()
            let metadata = try validateMetadata()
            try validateAggregateRectangle(metadata)
            cityBoundary = try loadCityBoundary()
            preparedNeighborhoods = try loadNeighborhoods()
            validatedMetadata = metadata
        } catch {
            if let database { sqlite3_close(database) }
            database = nil
            throw error
        }
    }

    deinit {
        if let database { sqlite3_close(database) }
    }

    public func scan(at coordinate: ScanCoordinate) throws -> ChicagoScanResult {
        guard coordinate.isGeographicallyValid, ChicagoBounds.contains(coordinate) else {
            throw ChicagoPackError.outsideChicago
        }

        guard let metadata = validatedMetadata else {
            throw ChicagoPackError.invalidDatabase("pack metadata was not validated")
        }
        let snappedCenter = snappedLocalDecimeters(coordinate)
        guard polygonsContain(cityBoundary, coordinate: coordinate) else {
            throw ChicagoPackError.outsideChicago
        }
        guard hasCompleteCoverage(around: snappedCenter, boundary: cityBoundary) else {
            throw ChicagoPackError.insufficientCellCoverage
        }
        let neighborhood = try officialNeighborhood(containing: coordinate)
        let estimate = try estimatedCircle(around: snappedCenter, metadata: metadata)
        let roundedCounts = balancedRoundedCounts(
            estimate.categoryNumerators,
            divisor: estimate.divisor,
            target: estimate.roundedTotal
        )
        let categoryCounts = zip(IncidentCategory.allCases, roundedCounts).map {
            CategoryCount(category: $0.0, count: $0.1)
        }
        let percentile = try midrankPercentile(for: estimate.roundedTotal)
        let roundedScore = max(0, min(100, Int(floor(percentile / 5 + 0.5)) * 5))

        return ChicagoScanResult(
            cookedScore: roundedScore,
            chicagoPercentile: percentile,
            estimatedIncidentCount: estimate.roundedTotal,
            categoryCounts: categoryCounts,
            neighborhood: neighborhood,
            sourceThroughDate: metadata.sourceThroughDate,
            periodStart: metadata.periodStart,
            methodologyVersion: metadata.methodologyVersion
        )
    }

    public func metadataValue(for key: String) throws -> String? {
        let statement = try prepare("SELECT value FROM metadata WHERE key = ? LIMIT 1")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, key, -1, destructor)
        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            guard let text = sqlite3_column_text(statement, 0) else { return nil }
            return String(cString: text)
        case SQLITE_DONE:
            return nil
        default:
            throw lastError()
        }
    }

    private struct LocalDecimeters {
        let x: Int64
        let y: Int64
    }

    private struct CircleEstimate {
        let categoryNumerators: [Int64]
        let divisor: Int64
        let roundedTotal: Int
    }

    private func estimatedCircle(
        around center: LocalDecimeters,
        metadata: PackMetadata
    ) throws -> CircleEstimate {
        let cellSize = Int64(Self.aggregateCellSizeMeters * 10)
        let radius = Int64(Self.radiusMeters * 10)
        let minimumRow = floorDiv(center.y - radius, by: cellSize)
        let maximumRow = floorDiv(center.y + radius, by: cellSize)
        let minimumColumn = floorDiv(center.x - radius, by: cellSize)
        let maximumColumn = floorDiv(center.x + radius, by: cellSize)
        guard metadata.aggregateRowRange.contains(minimumRow),
              metadata.aggregateRowRange.contains(maximumRow),
              metadata.aggregateColumnRange.contains(minimumColumn),
              metadata.aggregateColumnRange.contains(maximumColumn) else {
            throw ChicagoPackError.insufficientCellCoverage
        }

        let sql = """
        SELECT cell_row, cell_column,
               assault_battery_band, robbery_band, theft_band, motor_vehicle_theft_band
        FROM aggregate_cells
        WHERE cell_row BETWEEN ? AND ? AND cell_column BETWEEN ? AND ?
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, minimumRow)
        sqlite3_bind_int64(statement, 2, maximumRow)
        sqlite3_bind_int64(statement, 3, minimumColumn)
        sqlite3_bind_int64(statement, 4, maximumColumn)

        var categoryNumerators = [Int64](repeating: 0, count: IncidentCategory.allCases.count)
        var rowCount: Int64 = 0
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            let row = sqlite3_column_int64(statement, 0)
            let column = sqlite3_column_int64(statement, 1)
            let bands = (2 ... 5).map { sqlite3_column_int64(statement, Int32($0)) }
            let hits = overlapSubcellHits(
                cellRow: row,
                cellColumn: column,
                center: center,
                cellSizeDecimeters: cellSize,
                radiusDecimeters: radius
            )
            for index in categoryNumerators.indices {
                guard bands[index] <= Int64.max / max(hits, 1) else {
                    throw ChicagoPackError.invalidDatabase("aggregate band exceeds the supported numeric range")
                }
                let contribution = bands[index] * hits
                guard categoryNumerators[index] <= Int64.max - contribution else {
                    throw ChicagoPackError.invalidDatabase("aggregate estimate exceeds the supported numeric range")
                }
                categoryNumerators[index] += contribution
            }
            rowCount += 1
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else { throw lastError() }
        let expectedRows = (maximumRow - minimumRow + 1) * (maximumColumn - minimumColumn + 1)
        guard rowCount == expectedRows else {
            throw ChicagoPackError.invalidDatabase("aggregate cell rectangle is incomplete")
        }

        let divisor = Int64(Self.overlapSubcellsPerAxis * Self.overlapSubcellsPerAxis)
        let totalNumerator = categoryNumerators.reduce(0, +)
        guard totalNumerator <= Int64.max - divisor / 2 else {
            throw ChicagoPackError.invalidDatabase("estimated total exceeds the supported numeric range")
        }
        let roundedTotal = Int((totalNumerator + divisor / 2) / divisor)
        return CircleEstimate(
            categoryNumerators: categoryNumerators,
            divisor: divisor,
            roundedTotal: roundedTotal
        )
    }

    private func overlapSubcellHits(
        cellRow: Int64,
        cellColumn: Int64,
        center: LocalDecimeters,
        cellSizeDecimeters: Int64,
        radiusDecimeters: Int64
    ) -> Int64 {
        let subcellSize = Int64(Self.overlapSubcellSizeMeters * 10)
        let subcellHalfSize = subcellSize / 2
        let cellBaseX = cellColumn * cellSizeDecimeters
        let cellBaseY = cellRow * cellSizeDecimeters
        let radiusSquared = radiusDecimeters * radiusDecimeters
        var hits: Int64 = 0
        for subcellRow in 0 ..< Self.overlapSubcellsPerAxis {
            let y = cellBaseY + subcellHalfSize + Int64(subcellRow) * subcellSize
            let deltaY = y - center.y
            for subcellColumn in 0 ..< Self.overlapSubcellsPerAxis {
                let x = cellBaseX + subcellHalfSize + Int64(subcellColumn) * subcellSize
                let deltaX = x - center.x
                if deltaX * deltaX + deltaY * deltaY <= radiusSquared {
                    hits += 1
                }
            }
        }
        return hits
    }

    private func snappedLocalDecimeters(_ coordinate: ScanCoordinate) -> LocalDecimeters {
        let anchorLatitudeRadians = Self.gridAnchorLatitude * .pi / 180
        let xMeters = (coordinate.longitude - Self.gridAnchorLongitude) * .pi / 180
            * Self.earthRadiusMeters * cos(anchorLatitudeRadians)
        let yMeters = (coordinate.latitude - Self.gridAnchorLatitude) * .pi / 180
            * Self.earthRadiusMeters
        let snappedX = (xMeters / Self.scanCoordinateSnapMeters)
            .rounded(.toNearestOrAwayFromZero) * Self.scanCoordinateSnapMeters
        let snappedY = (yMeters / Self.scanCoordinateSnapMeters)
            .rounded(.toNearestOrAwayFromZero) * Self.scanCoordinateSnapMeters
        return LocalDecimeters(x: Int64(snappedX * 10), y: Int64(snappedY * 10))
    }

    private func coordinate(from local: LocalDecimeters) -> ScanCoordinate {
        let xMeters = Double(local.x) / 10
        let yMeters = Double(local.y) / 10
        let latitude = Self.gridAnchorLatitude + yMeters / Self.earthRadiusMeters * 180 / .pi
        let longitude = Self.gridAnchorLongitude + xMeters
            / (Self.earthRadiusMeters * cos(Self.gridAnchorLatitude * .pi / 180)) * 180 / .pi
        return ScanCoordinate(latitude: latitude, longitude: longitude)
    }

    private func hasCompleteCoverage(around center: LocalDecimeters, boundary: [GeoPolygon]) -> Bool {
        let latticeStep = Int64(Self.coverageLatticeSpacingMeters * 10)
        let radius = Int64(Self.radiusMeters * 10)
        var deltaY = -radius
        while deltaY <= radius {
            var deltaX = -radius
            while deltaX <= radius {
                if deltaX * deltaX + deltaY * deltaY <= radius * radius {
                    let sample = coordinate(from: LocalDecimeters(x: center.x + deltaX, y: center.y + deltaY))
                    guard polygonsContain(boundary, coordinate: sample) else { return false }
                }
                deltaX += latticeStep
            }
            deltaY += latticeStep
        }
        return true
    }

    private func floorDiv(_ value: Int64, by divisor: Int64) -> Int64 {
        let quotient = value / divisor
        let remainder = value % divisor
        return remainder < 0 ? quotient - 1 : quotient
    }

    private func midrankPercentile(for estimatedCount: Int) throws -> Double {
        let sql = """
        SELECT
          COALESCE(SUM(CASE WHEN estimated_count < ? THEN sample_count ELSE 0 END), 0),
          COALESCE(SUM(CASE WHEN estimated_count = ? THEN sample_count ELSE 0 END), 0),
          COALESCE(SUM(sample_count), 0)
        FROM reference_distribution
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, sqlite3_int64(estimatedCount))
        sqlite3_bind_int64(statement, 2, sqlite3_int64(estimatedCount))
        guard sqlite3_step(statement) == SQLITE_ROW else { throw lastError() }
        let below = Double(sqlite3_column_int64(statement, 0))
        let tied = Double(sqlite3_column_int64(statement, 1))
        let total = Double(sqlite3_column_int64(statement, 2))
        guard total > 0 else { throw ChicagoPackError.noEligibleReferences }
        return ((below + 0.5 * tied) / total) * 100
    }

    private func balancedRoundedCounts(
        _ numerators: [Int64],
        divisor: Int64,
        target: Int
    ) -> [Int] {
        let floors = numerators.map { Int($0 / divisor) }
        var result = floors
        let remainder = max(0, min(numerators.count, target - floors.reduce(0, +)))
        let ranked = numerators.indices.sorted {
            let left = numerators[$0] % divisor
            let right = numerators[$1] % divisor
            return left == right ? $0 < $1 : left > right
        }
        for index in ranked.prefix(remainder) { result[index] += 1 }
        return result
    }

    private func loadCityBoundary() throws -> [GeoPolygon] {
        let sql = "SELECT geometry_json FROM city_boundary WHERE id = 1 LIMIT 1"
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let text = sqlite3_column_text(statement, 0) else {
            throw ChicagoPackError.invalidDatabase("official Chicago boundary is unavailable")
        }
        guard let polygons = decodedPolygons(from: String(cString: text)) else {
            throw ChicagoPackError.invalidDatabase("official Chicago boundary geometry is invalid")
        }
        return polygons
    }

    private func officialNeighborhood(containing coordinate: ScanCoordinate) throws -> String {
        for neighborhood in preparedNeighborhoods where
            neighborhood.latitudeRange.contains(coordinate.latitude)
                && neighborhood.longitudeRange.contains(coordinate.longitude) {
            if polygonsContain(neighborhood.polygons, coordinate: coordinate) {
                return neighborhood.name
            }
        }
        throw ChicagoPackError.outsideChicago
    }

    private struct GeoPoint {
        let longitude: Double
        let latitude: Double
    }

    private struct GeoEdge {
        let current: GeoPoint
        let previous: GeoPoint
    }

    private struct GeoRing {
        let latitudeRange: ClosedRange<Double>
        let longitudeRange: ClosedRange<Double>
        let edgesByLatitudeBucket: [Int: [GeoEdge]]

        init?(points: [GeoPoint]) {
            guard points.count >= 3,
                  let minimumLatitude = points.map(\.latitude).min(),
                  let maximumLatitude = points.map(\.latitude).max(),
                  let minimumLongitude = points.map(\.longitude).min(),
                  let maximumLongitude = points.map(\.longitude).max() else { return nil }
            latitudeRange = minimumLatitude ... maximumLatitude
            longitudeRange = minimumLongitude ... maximumLongitude
            var buckets: [Int: [GeoEdge]] = [:]
            var previous = points[points.count - 1]
            for current in points {
                let edge = GeoEdge(current: current, previous: previous)
                let firstBucket = Int(floor(min(current.latitude, previous.latitude) * 1_000))
                let lastBucket = Int(floor(max(current.latitude, previous.latitude) * 1_000))
                for bucket in firstBucket ... lastBucket {
                    buckets[bucket, default: []].append(edge)
                }
                previous = current
            }
            edgesByLatitudeBucket = buckets
        }
    }

    private typealias GeoPolygon = [GeoRing]

    private struct PreparedNeighborhood {
        let name: String
        let latitudeRange: ClosedRange<Double>
        let longitudeRange: ClosedRange<Double>
        let polygons: [GeoPolygon]
    }

    private func loadNeighborhoods() throws -> [PreparedNeighborhood] {
        let statement = try prepare("""
            SELECT name, min_lat, max_lat, min_lon, max_lon, geometry_json
            FROM neighborhoods
            ORDER BY id
            """)
        defer { sqlite3_finalize(statement) }
        var neighborhoods: [PreparedNeighborhood] = []
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            guard let nameText = sqlite3_column_text(statement, 0),
                  let geometryText = sqlite3_column_text(statement, 5),
                  let polygons = decodedPolygons(from: String(cString: geometryText)) else {
                throw ChicagoPackError.invalidDatabase("official neighborhood geometry is invalid")
            }
            let minimumLatitude = sqlite3_column_double(statement, 1)
            let maximumLatitude = sqlite3_column_double(statement, 2)
            let minimumLongitude = sqlite3_column_double(statement, 3)
            let maximumLongitude = sqlite3_column_double(statement, 4)
            guard minimumLatitude <= maximumLatitude, minimumLongitude <= maximumLongitude else {
                throw ChicagoPackError.invalidDatabase("official neighborhood bounds are invalid")
            }
            neighborhoods.append(PreparedNeighborhood(
                name: String(cString: nameText),
                latitudeRange: minimumLatitude ... maximumLatitude,
                longitudeRange: minimumLongitude ... maximumLongitude,
                polygons: polygons
            ))
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE, !neighborhoods.isEmpty else {
            throw ChicagoPackError.invalidDatabase("official neighborhoods are unavailable")
        }
        return neighborhoods
    }

    private func decodedPolygons(from json: String) -> [GeoPolygon]? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String,
              let coordinates = object["coordinates"] as? [Any] else { return nil }
        switch type {
        case "Polygon":
            guard let polygon = decodedPolygon(coordinates) else { return nil }
            return [polygon]
        case "MultiPolygon":
            let polygons = coordinates.compactMap { raw -> GeoPolygon? in
                guard let polygon = raw as? [Any] else { return nil }
                return decodedPolygon(polygon)
            }
            return polygons.count == coordinates.count && !polygons.isEmpty ? polygons : nil
        default:
            return nil
        }
    }

    private func decodedPolygon(_ rawRings: [Any]) -> GeoPolygon? {
        let rings = rawRings.compactMap { rawRing -> GeoRing? in
            guard let rawPoints = rawRing as? [Any] else { return nil }
            let points = rawPoints.compactMap { rawPoint -> GeoPoint? in
                guard let values = rawPoint as? [Any], values.count >= 2,
                      let longitude = values[0] as? NSNumber,
                      let latitude = values[1] as? NSNumber else { return nil }
                return GeoPoint(longitude: longitude.doubleValue, latitude: latitude.doubleValue)
            }
            guard points.count == rawPoints.count else { return nil }
            return GeoRing(points: points)
        }
        return rings.count == rawRings.count && !rings.isEmpty ? rings : nil
    }

    private func polygonsContain(_ polygons: [GeoPolygon], coordinate: ScanCoordinate) -> Bool {
        polygons.contains { polygonContains($0, coordinate: coordinate) }
    }

    private func polygonContains(_ rings: GeoPolygon, coordinate: ScanCoordinate) -> Bool {
        guard let exterior = rings.first,
              ringContains(exterior, coordinate: coordinate) else { return false }
        return !rings.dropFirst().contains { ringContains($0, coordinate: coordinate) }
    }

    private func ringContains(_ ring: GeoRing, coordinate: ScanCoordinate) -> Bool {
        guard ring.latitudeRange.contains(coordinate.latitude),
              ring.longitudeRange.contains(coordinate.longitude) else { return false }
        let bucket = Int(floor(coordinate.latitude * 1_000))
        guard let edges = ring.edgesByLatitudeBucket[bucket] else { return false }
        var inside = false
        for edge in edges {
            let current = edge.current
            let previous = edge.previous
            let crossesLatitude = (current.latitude > coordinate.latitude) != (previous.latitude > coordinate.latitude)
            if crossesLatitude {
                let longitudeAtLatitude = (previous.longitude - current.longitude)
                    * (coordinate.latitude - current.latitude)
                    / (previous.latitude - current.latitude)
                    + current.longitude
                if coordinate.longitude < longitudeAtLatitude { inside.toggle() }
            }
        }
        return inside
    }

    private func validateMetadata() throws -> PackMetadata {
        let schema = try requiredMetadata("schema_version")
        guard schema == Self.supportedSchemaVersion else {
            throw ChicagoPackError.unsupportedSchema(schema)
        }

        let sourceThroughDate = try requiredMetadata("source_through_date")
        let periodStart = try requiredMetadata("period_start")
        guard isISODate(sourceThroughDate), isISODate(periodStart) else {
            throw ChicagoPackError.invalidDatabase("source dates must use YYYY-MM-DD")
        }

        let methodologyVersion = try requiredMetadata("methodology_version")
        guard methodologyVersion == Self.supportedMethodologyVersion else {
            throw ChicagoPackError.invalidDatabase("unsupported methodology metadata")
        }
        guard try requiredMetadata("disclaimer") == ChicagoScanResult.requiredDisclaimer else {
            throw ChicagoPackError.invalidDatabase("required disclaimer metadata does not match the app")
        }
        guard let radius = Double(try requiredMetadata("radius_m")),
              abs(radius - Self.radiusMeters) < 0.001 else {
            throw ChicagoPackError.invalidDatabase("radius metadata must be 500 meters")
        }
        guard let cellSize = Double(try requiredMetadata("aggregate_cell_size_m")),
              abs(cellSize - Self.aggregateCellSizeMeters) < 0.001,
              Int(try requiredMetadata("aggregate_band_size")) == Self.aggregateBandSize,
              try requiredMetadata("aggregate_band_rounding") == "nearest_5_half_up" else {
            throw ChicagoPackError.invalidDatabase("aggregate-cell or quantization metadata is unsupported")
        }
        guard let snap = Double(try requiredMetadata("scan_coordinate_snap_m")),
              abs(snap - Self.scanCoordinateSnapMeters) < 0.001,
              Int(try requiredMetadata("overlap_subcells_per_axis")) == Self.overlapSubcellsPerAxis,
              let subcellSize = Double(try requiredMetadata("overlap_subcell_size_m")),
              abs(subcellSize - Self.overlapSubcellSizeMeters) < 0.001,
              try requiredMetadata("circle_estimator") == "area_weighted_10x10_subcell_midpoint_integer_dm",
              try requiredMetadata("estimated_count_rounding") == "nearest_integer_half_up" else {
            throw ChicagoPackError.invalidDatabase("circle-estimator metadata is unsupported")
        }
        guard let anchorLatitude = Double(try requiredMetadata("grid_anchor_latitude")),
              abs(anchorLatitude - Self.gridAnchorLatitude) < 0.000_000_1,
              let anchorLongitude = Double(try requiredMetadata("grid_anchor_longitude")),
              abs(anchorLongitude - Self.gridAnchorLongitude) < 0.000_000_1,
              let earthRadius = Double(try requiredMetadata("earth_radius_m")),
              abs(earthRadius - Self.earthRadiusMeters) < 0.000_1 else {
            throw ChicagoPackError.invalidDatabase("local projection metadata is unsupported")
        }
        guard try requiredMetadata("pack_privacy") == Self.requiredPackPrivacy else {
            throw ChicagoPackError.invalidDatabase("pack privacy metadata does not match the non-overlapping quantized-cell contract")
        }
        guard try requiredMetadata("percentile_method") == "empirical_midrank",
              try requiredMetadata("display_rounding") == "nearest_5_half_up" else {
            throw ChicagoPackError.invalidDatabase("percentile or display-rounding metadata is unsupported")
        }
        guard try requiredMetadata("count_semantics") == Self.requiredCountSemantics,
              Int(try requiredMetadata("coverage_disk_lattice_samples")) == Self.coverageDiskLatticeSamples,
              let referenceSpacing = Double(try requiredMetadata("reference_spacing_m")),
              abs(referenceSpacing - Self.referenceSpacingMeters) < 0.001,
              try requiredMetadata("reference_eligibility") == Self.requiredReferenceEligibility,
              try requiredMetadata("ordinary_scan_network_policy") == Self.requiredNetworkPolicy else {
            throw ChicagoPackError.invalidDatabase("estimate, coverage, reference, or network-policy metadata is unsupported")
        }

        guard let rowMinimum = Int64(try requiredMetadata("aggregate_row_min")),
              let rowMaximum = Int64(try requiredMetadata("aggregate_row_max")),
              let columnMinimum = Int64(try requiredMetadata("aggregate_column_min")),
              let columnMaximum = Int64(try requiredMetadata("aggregate_column_max")),
              let aggregateCellCount = Int64(try requiredMetadata("aggregate_cell_count")),
              rowMinimum <= rowMaximum,
              columnMinimum <= columnMaximum,
              aggregateCellCount > 0 else {
            throw ChicagoPackError.invalidDatabase("aggregate rectangle metadata is invalid")
        }

        return PackMetadata(
            sourceThroughDate: sourceThroughDate,
            periodStart: periodStart,
            methodologyVersion: methodologyVersion,
            aggregateRowRange: rowMinimum ... rowMaximum,
            aggregateColumnRange: columnMinimum ... columnMaximum,
            aggregateCellCount: aggregateCellCount
        )
    }

    private func validateTableContracts() throws {
        let aggregateColumns = try tableColumns("aggregate_cells")
        guard aggregateColumns == [
            "cell_row", "cell_column", "assault_battery_band", "robbery_band",
            "theft_band", "motor_vehicle_theft_band"
        ] else {
            throw ChicagoPackError.invalidDatabase("aggregate_cells columns do not match schema v3")
        }
        guard try tableColumns("reference_distribution") == ["estimated_count", "sample_count"] else {
            throw ChicagoPackError.invalidDatabase("reference_distribution columns do not match schema v3")
        }
        guard try !hasRow("""
            SELECT 1 FROM aggregate_cells
            WHERE typeof(cell_row) != 'integer'
               OR typeof(cell_column) != 'integer'
               OR typeof(assault_battery_band) != 'integer'
               OR typeof(robbery_band) != 'integer'
               OR typeof(theft_band) != 'integer'
               OR typeof(motor_vehicle_theft_band) != 'integer'
               OR assault_battery_band < 0 OR assault_battery_band > 1000000 OR assault_battery_band % 5 != 0
               OR robbery_band < 0 OR robbery_band > 1000000 OR robbery_band % 5 != 0
               OR theft_band < 0 OR theft_band > 1000000 OR theft_band % 5 != 0
               OR motor_vehicle_theft_band < 0 OR motor_vehicle_theft_band > 1000000 OR motor_vehicle_theft_band % 5 != 0
            LIMIT 1
            """) else {
            throw ChicagoPackError.invalidDatabase("aggregate cells contain an invalid independently quantized band")
        }
        guard try !hasRow("""
            SELECT 1 FROM reference_distribution
            WHERE typeof(estimated_count) != 'integer'
               OR typeof(sample_count) != 'integer'
               OR estimated_count < 0 OR sample_count <= 0
            LIMIT 1
            """) else {
            throw ChicagoPackError.invalidDatabase("reference distribution contains an invalid row")
        }
    }

    private func validateAggregateRectangle(_ metadata: PackMetadata) throws {
        let rowCount = metadata.aggregateRowRange.upperBound - metadata.aggregateRowRange.lowerBound + 1
        let columnCount = metadata.aggregateColumnRange.upperBound - metadata.aggregateColumnRange.lowerBound + 1
        guard rowCount > 0, rowCount <= 1_000,
              columnCount > 0, columnCount <= 1_000 else {
            throw ChicagoPackError.invalidDatabase("aggregate rectangle dimensions are unsupported")
        }
        guard metadata.aggregateCellCount == rowCount * columnCount else {
            throw ChicagoPackError.invalidDatabase("aggregate cell count does not equal the declared rectangle")
        }
        let statement = try prepare("""
            SELECT MIN(cell_row), MAX(cell_row), MIN(cell_column), MAX(cell_column), COUNT(*)
            FROM aggregate_cells
            """)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              sqlite3_column_int64(statement, 0) == metadata.aggregateRowRange.lowerBound,
              sqlite3_column_int64(statement, 1) == metadata.aggregateRowRange.upperBound,
              sqlite3_column_int64(statement, 2) == metadata.aggregateColumnRange.lowerBound,
              sqlite3_column_int64(statement, 3) == metadata.aggregateColumnRange.upperBound,
              sqlite3_column_int64(statement, 4) == metadata.aggregateCellCount else {
            throw ChicagoPackError.invalidDatabase("aggregate cell rectangle is incomplete or inconsistent with metadata")
        }
    }

    private func tableColumns(_ name: String) throws -> [String] {
        let statement = try prepare("PRAGMA table_info(\(name))")
        defer { sqlite3_finalize(statement) }
        var columns: [String] = []
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            guard let text = sqlite3_column_text(statement, 1) else {
                throw ChicagoPackError.invalidDatabase("table \(name) contains an unnamed column")
            }
            columns.append(String(cString: text))
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else { throw lastError() }
        return columns
    }

    private func hasRow(_ sql: String) throws -> Bool {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        switch sqlite3_step(statement) {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default: throw lastError()
        }
    }

    private func requiredMetadata(_ key: String) throws -> String {
        guard let value = try metadataValue(for: key), !value.isEmpty else {
            throw ChicagoPackError.invalidDatabase("required metadata \(key) is missing")
        }
        return value
    }

    private func isISODate(_ value: String) -> Bool {
        guard value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else {
            return false
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: value) != nil
    }

    private func tableExists(_ name: String) throws -> Bool {
        let statement = try prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, name, -1, destructor)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard let database, sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError()
        }
        return statement
    }

    private func lastError() -> ChicagoPackError {
        let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "database is closed"
        return .invalidDatabase(message)
    }

}

public enum ChicagoBounds {
    public static let north = 42.0230
    public static let south = 41.6440
    public static let west = -87.9401
    public static let east = -87.5240

    public static func contains(_ coordinate: ScanCoordinate) -> Bool {
        (south ... north).contains(coordinate.latitude) && (west ... east).contains(coordinate.longitude)
    }
}
