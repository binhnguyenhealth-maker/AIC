import AICCore
import Foundation
import SQLite3

enum ValidationError: Error {
    case couldNotOpenPack
    case noSupportedCoordinate
    case failed(String)
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw ValidationError.failed(message) }
}

func neighborhoodCentroids(in url: URL) throws -> [ScanCoordinate] {
    var database: OpaquePointer?
    guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
          let database else { throw ValidationError.couldNotOpenPack }
    defer { sqlite3_close(database) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(
        database,
        """
        SELECT latitude, longitude
        FROM neighborhood_centroids
        ORDER BY name
        """,
        -1,
        &statement,
        nil
    ) == SQLITE_OK,
    let statement else { throw ValidationError.noSupportedCoordinate }
    defer { sqlite3_finalize(statement) }
    var coordinates: [ScanCoordinate] = []
    while sqlite3_step(statement) == SQLITE_ROW {
        coordinates.append(ScanCoordinate(
            latitude: sqlite3_column_double(statement, 0),
            longitude: sqlite3_column_double(statement, 1)
        ))
    }
    guard !coordinates.isEmpty else { throw ValidationError.noSupportedCoordinate }
    return coordinates
}

func offset(_ coordinate: ScanCoordinate, meters: Double, angleDegrees: Double) -> ScanCoordinate {
    let angle = angleDegrees * .pi / 180
    let latitude = coordinate.latitude + meters * sin(angle) / 111_320
    let longitudeScale = max(cos(coordinate.latitude * .pi / 180), 0.01)
    let longitude = coordinate.longitude + meters * cos(angle) / (111_320 * longitudeScale)
    return ScanCoordinate(latitude: latitude, longitude: longitude)
}

func quantile(_ sortedValues: [Double], _ probability: Double) throws -> Double {
    guard !sortedValues.isEmpty else { throw ValidationError.failed("empty metric sample") }
    let index = min(sortedValues.count - 1, max(0, Int(ceil(probability * Double(sortedValues.count))) - 1))
    return sortedValues[index]
}

let packPath = CommandLine.arguments.dropFirst().first ?? "AIC/Resources/chicago_beta.sqlite"
let packURL = URL(fileURLWithPath: packPath)
let pack = try ChicagoPack(url: packURL)
let parityFixtures: [(ScanCoordinate, [Int], Int, Double, Int, String)] = [
    (
        ScanCoordinate(latitude: 41.74838786001455, longitude: -87.67339634684177),
        [108, 5, 41, 21], 175, 57.938092860708934, 60, "Auburn Gresham"
    ),
    (
        ScanCoordinate(latitude: 41.82483009093114, longitude: -87.6373176094733),
        [105, 5, 44, 27], 181, 59.41088367448827, 60, "Bridgeport"
    ),
    (
        ScanCoordinate(latitude: 41.92825193275946, longitude: -87.7996719276314),
        [56, 0, 25, 11], 92, 35.222166749875186, 35, "Montclare"
    )
]
try require(
    IncidentCategory.allCases.map(\.rawValue)
        == ["assault_battery", "robbery", "theft", "motor_vehicle_theft"],
    "Swift category order drifted from the schema-v3 contract"
)
for (fixtureCoordinate, categories, total, percentile, score, neighborhood) in parityFixtures {
    let fixtureResult = try pack.scan(at: fixtureCoordinate)
    try require(fixtureResult.categoryCounts.map(\.count) == categories, "cross-language category parity failed")
    try require(fixtureResult.estimatedIncidentCount == total, "cross-language estimated-total parity failed")
    try require(abs(fixtureResult.chicagoPercentile - percentile) < 0.000_000_001, "cross-language percentile parity failed")
    try require(fixtureResult.cookedScore == score, "cross-language score parity failed")
    try require(fixtureResult.neighborhood == neighborhood, "cross-language community-area parity failed")
}
let centroids = try neighborhoodCentroids(in: packURL)
var sampleCoordinates: [ScanCoordinate] = []
for (index, centroid) in centroids.enumerated() {
    for (distance, angle) in [(0.0, 0.0), (100.0, 45.0), (200.0, 137.0), (300.0, 251.0)] {
        let candidate = offset(centroid, meters: distance, angleDegrees: angle + Double(index % 17))
        if (try? pack.scan(at: candidate)) != nil { sampleCoordinates.append(candidate) }
    }
}
try require(sampleCoordinates.count >= 50, "fewer than 50 representative Chicago points support a complete estimate")
let coordinate = sampleCoordinates[0]
let result = try pack.scan(at: coordinate)

try require(result.cookedScore.isMultiple(of: 5), "score is not rounded to nearest five")
try require((0 ... 100).contains(result.cookedScore), "score is outside 0...100")
try require((0 ... 100).contains(result.chicagoPercentile), "percentile is outside 0...100")
try require(
    result.categoryCounts.reduce(0) { $0 + $1.count } == result.estimatedIncidentCount,
    "balanced category estimates do not reconcile to the rounded estimated total"
)
try require(
    ChicagoScanResult.requiredDisclaimer == "Cooked Score is a historical data index that compares reported-incident concentration around this location with eligible Chicago comparison locations. It is not a live safety assessment or personal-risk prediction.",
    "required disclaimer drifted"
)
let packDisclaimer = try pack.metadataValue(for: "disclaimer")
try require(
    packDisclaimer == ChicagoScanResult.requiredDisclaimer,
    "pack and app disclaimers do not match"
)
let packPrivacy = try pack.metadataValue(for: "pack_privacy")
try require(
    packPrivacy == ChicagoPack.requiredPackPrivacy,
    "pack privacy contract is missing"
)
let packSchemaVersion = try pack.metadataValue(for: "schema_version")
try require(
    packSchemaVersion == ChicagoPack.supportedSchemaVersion,
    "schema v3 is not active"
)
let packMethodologyVersion = try pack.metadataValue(for: "methodology_version")
try require(
    packMethodologyVersion == ChicagoPack.supportedMethodologyVersion,
    "methodology v3 is not active"
)
try require(
    ChicagoScanResult.estimateDisclosure.lowercased().contains("estimates"),
    "estimated-count disclosure drifted"
)
try require(
    UsernamePolicy.validate("chi_beta_7") == .valid(normalized: "chi_beta_7"),
    "username policy rejected a valid handle"
)

let receipt = ReceiptComposer.make(
    result: result,
    username: "chi_beta_7",
    showUsername: false,
    locationMode: .hidden
)
let encoded = try JSONEncoder().encode(receipt)
let object = try JSONSerialization.jsonObject(with: encoded)
try require(ReceiptPrivacyAudit.forbiddenKeys(in: object).isEmpty, "receipt encoded a precise-location field")
try require(receipt.username == nil && receipt.locationLabel == nil, "receipt visibility controls failed")

// Exclude pack opening and the first scan from the latency sample.
_ = try pack.scan(at: sampleCoordinates[0])
var scanMilliseconds: [Double] = []
for coordinate in sampleCoordinates.prefix(100) {
    let start = Date.timeIntervalSinceReferenceDate
    _ = try pack.scan(at: coordinate)
    scanMilliseconds.append((Date.timeIntervalSinceReferenceDate - start) * 1_000)
}
scanMilliseconds.sort()
let scanMedian = try quantile(scanMilliseconds, 0.50)
let scanP95 = try quantile(scanMilliseconds, 0.95)
try require(scanP95 <= 250, "actual-pack scan p95 exceeds 250 ms")

var scoreDeltas: [Double] = []
var attemptedMovements = 0
for (index, coordinate) in sampleCoordinates.prefix(200).enumerated() {
    let base = try pack.scan(at: coordinate)
    for meters in [10.0, 20.0, 30.0, 40.0, 50.0] {
        attemptedMovements += 1
        let angle = Double((index * 137 + Int(meters) * 31) % 360)
        do {
            let moved = try pack.scan(at: offset(coordinate, meters: meters, angleDegrees: angle))
            scoreDeltas.append(Double(abs(moved.cookedScore - base.cookedScore)))
        } catch ChicagoPackError.insufficientCellCoverage {
            continue
        } catch ChicagoPackError.outsideChicago {
            continue
        }
    }
}
try require(scoreDeltas.count * 100 >= attemptedMovements * 95, "too many stability samples were unavailable")
scoreDeltas.sort()
let stabilityMedian = try quantile(scoreDeltas, 0.50)
let stabilityP95 = try quantile(scoreDeltas, 0.95)
try require(stabilityMedian <= 5, "10–50 m stability median exceeds 5 score points")
try require(stabilityP95 <= 10, "10–50 m stability p95 exceeds 10 score points")

print("AIC_CORE_VALIDATION_OK")
print("source_through=\(result.sourceThroughDate)")
print("methodology=\(result.methodologyVersion)")
print("score=\(result.cookedScore) percentile=\(String(format: "%.3f", result.chicagoPercentile)) estimated_incidents=\(result.estimatedIncidentCount)")
print("category_parity_fixtures=\(parityFixtures.count)")
print("scan_ms_median=\(String(format: "%.2f", scanMedian)) scan_ms_p95=\(String(format: "%.2f", scanP95)) n=\(scanMilliseconds.count)")
print("stability_delta_median=\(String(format: "%.1f", stabilityMedian)) stability_delta_p95=\(String(format: "%.1f", stabilityP95)) supported=\(scoreDeltas.count)/\(attemptedMovements)")
