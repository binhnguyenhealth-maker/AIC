import SQLite3
import XCTest
@testable import AICCore

final class ChicagoPackTests: XCTestCase {
    private let centerRow: Int64 = 124
    private let centerColumn: Int64 = 106
    private var databaseURL: URL!

    private var fixtureCoordinate: ScanCoordinate {
        let x = (Double(centerColumn) + 0.5) * ChicagoPack.aggregateCellSizeMeters
        let y = (Double(centerRow) + 0.5) * ChicagoPack.aggregateCellSizeMeters
        let latitude = ChicagoPack.gridAnchorLatitude
            + y / ChicagoPack.earthRadiusMeters * 180 / .pi
        let longitude = ChicagoPack.gridAnchorLongitude
            + x / (
                ChicagoPack.earthRadiusMeters
                    * cos(ChicagoPack.gridAnchorLatitude * .pi / 180)
            ) * 180 / .pi
        return ScanCoordinate(latitude: latitude, longitude: longitude)
    }

    override func setUpWithError() throws {
        databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        try createFixture(at: databaseURL)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: databaseURL)
    }

    func testComputesAreaWeightedEstimateAndMidrankPercentile() throws {
        let pack = try openFixturePack()
        let result = try pack.scan(at: fixtureCoordinate)

        XCTAssertEqual(result.estimatedIncidentCount, 632)
        XCTAssertEqual(result.categoryCounts.map(\.count), [63, 126, 190, 253])
        XCTAssertEqual(result.categoryCounts.reduce(0) { $0 + $1.count }, result.estimatedIncidentCount)
        XCTAssertEqual(result.chicagoPercentile, 60, accuracy: 0.001)
        XCTAssertEqual(result.cookedScore, 60)
        XCTAssertEqual(result.neighborhood, "Loop Test")
        XCTAssertEqual(result.sourceThroughDate, "2026-06-30")
        XCTAssertEqual(result.methodologyVersion, ChicagoPack.supportedMethodologyVersion)
    }

    func testScanSucceedsImmediatelyBeforeFreshnessBoundary() throws {
        let pack = try ChicagoPack(
            url: databaseURL,
            currentDateProvider: { self.date("2026-08-06T23:59:59Z") }
        )
        XCTAssertNoThrow(try pack.scan(at: fixtureCoordinate))
    }

    func testFreshnessSummaryExposesValidatedMetadataAndUTCDayCounts() throws {
        let summary = try ChicagoPack.inspectFreshness(
            at: databaseURL,
            currentDateProvider: { self.date("2026-07-12T23:59:59Z") }
        )

        XCTAssertEqual(summary.sourceThroughDate, "2026-06-30")
        XCTAssertEqual(summary.periodStart, "2025-07-01")
        XCTAssertEqual(summary.sourceRetrievedAt, date("2026-07-11T02:40:53Z"))
        XCTAssertEqual(summary.freshUntilDate, "2026-08-07")
        XCTAssertEqual(summary.expiresAtDate, "2026-08-29")
        XCTAssertEqual(summary.state, .withinUpdateWindow)
        XCTAssertEqual(summary.daysSinceSourceThrough, 12)
        XCTAssertEqual(summary.daysUntilCutoff, 26)
    }

    func testFreshnessStatesUseExactUTCSevenDayWindowAndCutoff() throws {
        let beforeWindow = try inspectFreshness(at: "2026-07-30T23:59:59Z")
        XCTAssertEqual(beforeWindow.state, .withinUpdateWindow)
        XCTAssertEqual(beforeWindow.daysUntilCutoff, 8)

        let dueSoon = try inspectFreshness(at: "2026-07-31T00:00:00Z")
        XCTAssertEqual(dueSoon.state, .updateDueSoon)
        XCTAssertEqual(dueSoon.daysUntilCutoff, 7)

        let finalFreshDay = try inspectFreshness(at: "2026-08-06T23:59:59Z")
        XCTAssertEqual(finalFreshDay.state, .updateDueSoon)
        XCTAssertEqual(finalFreshDay.daysUntilCutoff, 1)

        let blocked = try inspectFreshness(at: "2026-08-07T00:00:00Z")
        XCTAssertEqual(blocked.state, .blocked)
        XCTAssertEqual(blocked.daysUntilCutoff, 0)
        XCTAssertEqual(blocked.daysSinceSourceThrough, 38)
    }

    func testStalePackSummaryRemainsInspectableWhilePackOpenFailsClosed() throws {
        let now = { self.date("2026-08-12T12:00:00Z") }
        let summary = try ChicagoPack.inspectFreshness(
            at: databaseURL,
            currentDateProvider: now
        )
        XCTAssertEqual(summary.state, .blocked)
        XCTAssertEqual(summary.daysUntilCutoff, 0)

        XCTAssertThrowsError(try ChicagoPack(
            url: databaseURL,
            currentDateProvider: now
        )) { error in
            XCTAssertEqual(error as? ChicagoPackError, .packUpdateRequired)
        }
    }

    func testPackOpenFailsClosedOnFreshnessBoundary() throws {
        XCTAssertThrowsError(try ChicagoPack(
            url: databaseURL,
            currentDateProvider: { self.date("2026-08-07T00:00:00Z") }
        )) { error in
            XCTAssertEqual(error as? ChicagoPackError, .packUpdateRequired)
            XCTAssertEqual(
                (error as? ChicagoPackError)?.errorDescription,
                "This data pack needs an update before another scan. Please update the app and try again."
            )
        }
    }

    func testLongLivedPackStopsScanningAtFreshnessBoundary() throws {
        var currentDate = date("2026-08-06T23:59:59Z")
        let pack = try ChicagoPack(
            url: databaseURL,
            currentDateProvider: { currentDate }
        )
        currentDate = date("2026-08-07T00:00:00Z")
        XCTAssertThrowsError(try pack.scan(at: fixtureCoordinate)) { error in
            XCTAssertEqual(error as? ChicagoPackError, .packUpdateRequired)
        }
    }

    func testSubMeterMovementThatSnapsToSameMeterIsDeterministic() throws {
        let pack = try openFixturePack()
        let baseline = try pack.scan(at: fixtureCoordinate)
        let moved = ScanCoordinate(
            latitude: fixtureCoordinate.latitude + 0.4 / 111_320,
            longitude: fixtureCoordinate.longitude
        )
        XCTAssertEqual(try pack.scan(at: moved), baseline)
    }

    func testOfficialPolygonRejectsPointInsideRectangularBoundsButOutsideChicagoFixture() throws {
        let pack = try openFixturePack()
        XCTAssertThrowsError(try pack.scan(at: ScanCoordinate(latitude: 41.88, longitude: -87.55))) { error in
            XCTAssertEqual(error as? ChicagoPackError, .outsideChicago)
        }
    }

    func testBoundaryPointWithoutComplete500MeterCoverageFailsClosed() throws {
        let pack = try openFixturePack()
        XCTAssertThrowsError(try pack.scan(at: ScanCoordinate(latitude: 41.88, longitude: -87.6799))) { error in
            XCTAssertEqual(error as? ChicagoPackError, .insufficientCellCoverage)
        }
    }

    func testMissingAggregateCellFailsClosedAtPackOpen() throws {
        try mutate("DELETE FROM aggregate_cells WHERE cell_row = 124 AND cell_column = 106")
        XCTAssertThrowsError(try openFixturePack())
    }

    func testNonQuantizedCategoryBandIsRejected() throws {
        try mutate("""
            PRAGMA ignore_check_constraints = ON;
            UPDATE aggregate_cells SET robbery_band = 6 WHERE cell_row = 124 AND cell_column = 106;
            """)
        XCTAssertThrowsError(try openFixturePack())
    }

    func testResidualOrExactTotalColumnIsRejected() throws {
        try mutate("ALTER TABLE aggregate_cells ADD COLUMN total_count INTEGER")
        XCTAssertThrowsError(try openFixturePack())
    }

    func testMissingSchemaMetadataIsRejected() throws {
        try mutate("DELETE FROM metadata WHERE key = 'schema_version'")
        XCTAssertThrowsError(try openFixturePack())
    }

    func testMissingFreshnessMetadataIsRejected() throws {
        try mutate("DELETE FROM metadata WHERE key = 'fresh_until_date'")
        XCTAssertThrowsError(try openFixturePack())
    }

    func testMissingSourceRetrievedAtIsRejected() throws {
        try mutate("DELETE FROM metadata WHERE key = 'source_retrieved_at'")
        XCTAssertThrowsError(try openFixturePack()) { error in
            XCTAssertEqual(
                error as? ChicagoPackError,
                .invalidDatabase("required metadata source_retrieved_at is missing")
            )
        }
    }

    func testMalformedSourceRetrievedAtIsRejected() throws {
        try mutate("UPDATE metadata SET value = 'July 11, 2026' WHERE key = 'source_retrieved_at'")
        XCTAssertThrowsError(try openFixturePack())
    }

    func testSourceThroughAfterRetrievalIsRejected() throws {
        try mutate("UPDATE metadata SET value = '2026-06-29T23:59:59Z' WHERE key = 'source_retrieved_at'")
        XCTAssertThrowsError(try openFixturePack()) { error in
            XCTAssertEqual(
                error as? ChicagoPackError,
                .invalidDatabase(
                    "source chronology must start on or before source-through and be retrieved on or after source-through"
                )
            )
        }
    }

    func testPeriodStartAfterSourceThroughIsRejected() throws {
        try mutate("UPDATE metadata SET value = '2026-07-01' WHERE key = 'period_start'")
        XCTAssertThrowsError(try openFixturePack())
    }

    func testMalformedFreshnessMetadataIsRejected() throws {
        try mutate("UPDATE metadata SET value = '2026-99-99' WHERE key = 'expires_at_date'")
        XCTAssertThrowsError(try openFixturePack())
    }

    func testFreshnessMetadataThatDriftsFromPolicyIsRejected() throws {
        try mutate("UPDATE metadata SET value = '2026-08-08' WHERE key = 'fresh_until_date'")
        XCTAssertThrowsError(try openFixturePack())
    }

    func testMismatchedDisclaimerIsRejected() throws {
        try mutate("UPDATE metadata SET value = 'wrong' WHERE key = 'disclaimer'")
        XCTAssertThrowsError(try openFixturePack())
    }

    func testOldSchemaIsRejected() throws {
        try mutate("UPDATE metadata SET value = '2' WHERE key = 'schema_version'")
        XCTAssertThrowsError(try openFixturePack()) { error in
            XCTAssertEqual(error as? ChicagoPackError, .unsupportedSchema("2"))
        }
    }

    func testEstimatorMetadataDriftIsRejected() throws {
        try mutate("UPDATE metadata SET value = 'different' WHERE key = 'circle_estimator'")
        XCTAssertThrowsError(try openFixturePack())
    }

    private func createFixture(at url: URL) throws {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        let square = "{\"type\":\"Polygon\",\"coordinates\":[[[-87.68,41.83],[-87.58,41.83],[-87.58,41.93],[-87.68,41.93],[-87.68,41.83]]]}"
        let escapedSquare = square.replacingOccurrences(of: "'", with: "''")
        let rowMinimum = centerRow - 4
        let rowMaximum = centerRow + 4
        let columnMinimum = centerColumn - 4
        let columnMaximum = centerColumn + 4
        try execute(database, """
        CREATE TABLE metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL);
        INSERT INTO metadata VALUES
          ('schema_version','3'),
          ('source_through_date','2026-06-30'),
          ('source_retrieved_at','2026-07-11T02:40:53Z'),
          ('fresh_until_date','2026-08-07'),
          ('expires_at_date','2026-08-29'),
          ('period_start','2025-07-01'),
          ('methodology_version','beta-cell250-q5-area-v3'),
          ('radius_m','500.0'),
          ('aggregate_cell_size_m','250.0'),
          ('aggregate_band_size','5'),
          ('aggregate_band_rounding','nearest_5_half_up'),
          ('scan_coordinate_snap_m','1.0'),
          ('overlap_subcells_per_axis','10'),
          ('overlap_subcell_size_m','25.0'),
          ('circle_estimator','area_weighted_10x10_subcell_midpoint_integer_dm'),
          ('estimated_count_rounding','nearest_integer_half_up'),
          ('percentile_method','empirical_midrank'),
          ('display_rounding','nearest_5_half_up'),
          ('grid_anchor_latitude','41.6'),
          ('grid_anchor_longitude','-87.95'),
          ('earth_radius_m','6371008.8'),
          ('aggregate_row_min','\(rowMinimum)'),
          ('aggregate_row_max','\(rowMaximum)'),
          ('aggregate_column_min','\(columnMinimum)'),
          ('aggregate_column_max','\(columnMaximum)'),
          ('aggregate_cell_count','81'),
          ('pack_privacy','nonoverlapping_250m_cells_independent_q5_bands_no_exact_or_residual_total'),
          ('count_semantics','privacy_coarsened_estimated_contributing_incidents'),
          ('coverage_disk_lattice_samples','81'),
          ('reference_spacing_m','500.0'),
          ('reference_eligibility','all_100m_disk_lattice_points_inside_official_city_union'),
          ('ordinary_scan_network_policy','local_only_no_coordinates_query_nodes_or_geographic_cells_uploaded'),
          ('disclaimer','Cooked Score is a historical data index that compares reported-incident concentration around this location with eligible Chicago comparison locations. It is not a live safety assessment or personal-risk prediction.');
        CREATE TABLE aggregate_cells(
          cell_row INTEGER NOT NULL,
          cell_column INTEGER NOT NULL,
          assault_battery_band INTEGER NOT NULL CHECK(assault_battery_band >= 0 AND assault_battery_band % 5 = 0),
          robbery_band INTEGER NOT NULL CHECK(robbery_band >= 0 AND robbery_band % 5 = 0),
          theft_band INTEGER NOT NULL CHECK(theft_band >= 0 AND theft_band % 5 = 0),
          motor_vehicle_theft_band INTEGER NOT NULL CHECK(motor_vehicle_theft_band >= 0 AND motor_vehicle_theft_band % 5 = 0),
          PRIMARY KEY(cell_row,cell_column)
        ) WITHOUT ROWID;
        CREATE TABLE reference_distribution(estimated_count INTEGER PRIMARY KEY, sample_count INTEGER);
        INSERT INTO reference_distribution VALUES (0,2),(632,2),(700,1);
        CREATE TABLE neighborhood_centroids(latitude REAL, longitude REAL, name TEXT);
        INSERT INTO neighborhood_centroids VALUES (\(fixtureCoordinate.latitude),\(fixtureCoordinate.longitude),'Loop Test');
        CREATE TABLE neighborhoods(id INTEGER PRIMARY KEY,name TEXT,min_lat REAL,max_lat REAL,min_lon REAL,max_lon REAL,geometry_json TEXT);
        INSERT INTO neighborhoods VALUES (1,'Loop Test',41.83,41.93,-87.68,-87.58,'\(escapedSquare)');
        CREATE TABLE city_boundary(id INTEGER PRIMARY KEY,min_lat REAL,max_lat REAL,min_lon REAL,max_lon REAL,geometry_json TEXT);
        INSERT INTO city_boundary VALUES (1,41.83,41.93,-87.68,-87.58,'\(escapedSquare)');
        """)
        for row in rowMinimum ... rowMaximum {
            for column in columnMinimum ... columnMaximum {
                try execute(database, "INSERT INTO aggregate_cells VALUES (\(row),\(column),5,10,15,20)")
            }
        }
    }

    private func execute(_ database: OpaquePointer?, _ sql: String) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        let status = sqlite3_exec(database, sql, nil, nil, &errorPointer)
        if status != SQLITE_OK {
            let message = errorPointer.map { String(cString: $0) } ?? "SQLite fixture error"
            sqlite3_free(errorPointer)
            XCTFail(message)
            throw NSError(domain: "ChicagoPackTests", code: Int(status), userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private func date(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: value) else {
            XCTFail("invalid test date: \(value)")
            return .distantPast
        }
        return date
    }

    private func openFixturePack() throws -> ChicagoPack {
        try ChicagoPack(
            url: databaseURL,
            currentDateProvider: { self.date("2026-07-12T12:00:00Z") }
        )
    }

    private func inspectFreshness(at timestamp: String) throws -> PackFreshnessSummary {
        try ChicagoPack.inspectFreshness(
            at: databaseURL,
            currentDateProvider: { self.date(timestamp) }
        )
    }

    private func mutate(_ sql: String) throws {
        var database: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK else {
            throw NSError(domain: "ChicagoPackTests", code: 10)
        }
        defer { sqlite3_close(database) }
        try execute(database, sql)
    }
}
