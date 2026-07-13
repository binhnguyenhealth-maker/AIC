import AICCore
import SQLite3
import XCTest
@testable import AIC

final class LocalOperationNetworkPrivacyTests: XCTestCase {
    func testBundledPackMatchesCanonicalCrossLanguageCategoryParity() throws {
        let packURL = try XCTUnwrap(Bundle.main.url(forResource: "chicago_beta", withExtension: "sqlite"))
        let pack = try ChicagoPack(url: packURL)
        let fixtures: [(ScanCoordinate, [Int], Int, Double, Int, String)] = [
            (
                ScanCoordinate(latitude: 41.74838786001455, longitude: -87.67339634684177),
                [108, 5, 41, 21], 175, 57.888167748377434, 60, "Auburn Gresham"
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

        XCTAssertEqual(
            IncidentCategory.allCases.map(\.rawValue),
            ["assault_battery", "robbery", "theft", "motor_vehicle_theft"]
        )
        for (coordinate, categories, total, percentile, score, neighborhood) in fixtures {
            let result = try pack.scan(at: coordinate)
            XCTAssertEqual(result.categoryCounts.map(\.count), categories)
            XCTAssertEqual(result.estimatedIncidentCount, total)
            XCTAssertEqual(result.chicagoPercentile, percentile, accuracy: 0.000_000_001)
            XCTAssertEqual(result.cookedScore, score)
            XCTAssertEqual(result.neighborhood, neighborhood)
            XCTAssertEqual(result.sourceThroughDate, "2026-06-30")
        }
    }

    @MainActor
    func testCurrentManualScanReceiptAndCancelledShareMakeNoNetworkRequest() async throws {
        GlobalRecordingURLProtocol.reset()
        URLProtocol.registerClass(GlobalRecordingURLProtocol.self)
        defer { URLProtocol.unregisterClass(GlobalRecordingURLProtocol.self) }

        let packURL = try XCTUnwrap(Bundle.main.url(forResource: "chicago_beta", withExtension: "sqlite"))
        let engine = LocalScanEngine(
            packURL: packURL,
            statusAuthorizer: TestPackStatusAuthorizer()
        )
        var eligibleCoordinate: ScanCoordinate?
        var currentResultCandidate: ChicagoScanResult?
        for coordinate in try neighborhoodCentroids(in: packURL) {
            if let result = try? await engine.scan(at: coordinate) {
                eligibleCoordinate = coordinate
                currentResultCandidate = result
                break
            }
        }
        let coordinate = try XCTUnwrap(eligibleCoordinate)
        let currentLocationResult = try XCTUnwrap(currentResultCandidate)

        // Current-location and manual-pin flows converge on this same local-only engine.
        let manualPinResult = try await engine.scan(at: coordinate)
        XCTAssertEqual(currentLocationResult, manualPinResult)

        let payload = ReceiptComposer.make(
            result: manualPinResult,
            locationMode: .neighborhood
        )
        let artifact = try ReceiptArtifactRenderer.render(payload)
        // Cancelling the native share sheet has no AIC upload path; it only removes this local file.
        try FileManager.default.removeItem(at: artifact.fileURL)

        XCTAssertTrue(GlobalRecordingURLProtocol.requests.isEmpty)
    }

    private func neighborhoodCentroids(in url: URL) throws -> [ScanCoordinate] {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database else { throw NSError(domain: "AICPrivacyTests", code: 1) }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT latitude,longitude FROM neighborhood_centroids ORDER BY name",
            -1,
            &statement,
            nil
        ) == SQLITE_OK,
        let statement else { throw NSError(domain: "AICPrivacyTests", code: 2) }
        defer { sqlite3_finalize(statement) }
        var coordinates: [ScanCoordinate] = []
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            coordinates.append(ScanCoordinate(
                latitude: sqlite3_column_double(statement, 0),
                longitude: sqlite3_column_double(statement, 1)
            ))
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE, !coordinates.isEmpty else {
            throw NSError(domain: "AICPrivacyTests", code: 3)
        }
        return coordinates
    }
}

private struct TestPackStatusAuthorizer: PackStatusAuthorizing {
    func authorize(packAt _: URL, refresh _: Bool) async throws {}
}

private final class GlobalRecordingURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var storage: [URLRequest] = []

    static var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    static func reset() {
        lock.lock()
        storage = []
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.storage.append(request)
        Self.lock.unlock()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 418,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
