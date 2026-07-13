import AICCore
import XCTest
@testable import AIC

final class PackStatusClientTests: XCTestCase {
    func testBundledBootstrapIsThresholdSignedForExactBundledPack() throws {
        let statusURL = try XCTUnwrap(Bundle.main.url(
            forResource: "pack_status_bootstrap",
            withExtension: "json"
        ))
        let packURL = try XCTUnwrap(Bundle.main.url(
            forResource: "chicago_beta",
            withExtension: "sqlite"
        ))
        let verified = try PackStatusVerifier(
            trustAnchor: PackStatusClient.trustAnchor
        ).verify(
            envelopeData: Data(contentsOf: statusURL),
            now: Date(timeIntervalSince1970: 1_783_910_500)
        )
        let packSHA = try PackStatusVerifier.sha256Hex(fileAt: packURL)

        XCTAssertEqual(packSHA, "1a18629fa3429eefec10d0d025c80102ce7c48a63457e601c1c404001686ca32")
        XCTAssertEqual(verified.entry(forPackSHA256: packSHA)?.status, .active)
        XCTAssertEqual(verified.payload.sequence, 2)
    }

    func testGlobalStatusRequestContainsNoLocationOrClientIdentifier() throws {
        let endpoint = try XCTUnwrap(URL(
            string: "https://aic-beta-info.binhnguyenhealth.workers.dev/pack-status/v1/status.json"
        ))
        let request = PackStatusClient.statusRequest(url: endpoint)

        XCTAssertEqual(request.url, endpoint)
        XCTAssertNil(request.url?.query)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.httpBody)
        XCTAssertEqual(request.allHTTPHeaderFields, ["Accept": "application/json"])
        XCTAssertFalse(request.url!.absoluteString.localizedCaseInsensitiveContains("chicago"))
        XCTAssertFalse(request.url!.absoluteString.contains("1a18629"))
    }

    func testPersistedStatusRequiresNetworkRefreshInNewClientProcess() async throws {
        let endpoint = try XCTUnwrap(URL(
            string: "https://aic-beta-info.binhnguyenhealth.workers.dev/pack-status/v1/status.json"
        ))
        let statusURL = try XCTUnwrap(Bundle.main.url(
            forResource: "pack_status_bootstrap",
            withExtension: "json"
        ))
        let packURL = try XCTUnwrap(Bundle.main.url(
            forResource: "chicago_beta",
            withExtension: "sqlite"
        ))
        let envelopeData = try Data(contentsOf: statusURL)
        let verifier = PackStatusVerifier(trustAnchor: PackStatusClient.trustAnchor)
        let now = Date()
        let verified = try verifier.verify(envelopeData: envelopeData, now: now)
        let packSHA = try PackStatusVerifier.sha256Hex(fileAt: packURL)
        let uptime = ProcessInfo.processInfo.systemUptime
        let trustedTime = try PackStatusTrustedTime(
            wallClock: now,
            systemUptime: uptime
        )
        let persisted = PersistedPackStatus(
            envelopeData: envelopeData,
            checkpoint: verified.checkpoint(forPackSHA256: packSHA),
            verifiedWallClockUnix: trustedTime.wallClockFloorUnix,
            verifiedSystemUptime: trustedTime.anchorSystemUptime,
            verifiedBootTimeUnix: trustedTime.anchorBootTimeUnix
        )
        let store = InMemoryPackStatusStore(state: persisted)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FailingPackStatusURLProtocol.self]
        let client = PackStatusClient(
            endpointURL: endpoint,
            bootstrapData: envelopeData,
            verifier: verifier,
            stateStore: store,
            session: URLSession(configuration: configuration)
        )

        FailingPackStatusURLProtocol.reset()
        do {
            try await client.authorize(packAt: packURL, refresh: false)
            XCTFail("persisted status authorized without the mandatory process refresh")
        } catch {
            XCTAssertEqual(error as? PackStatusGateError, .statusUnavailable)
        }
        XCTAssertEqual(FailingPackStatusURLProtocol.requestCount, 1)
    }
}

private final class InMemoryPackStatusStore: PackStatusStateStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var state: PersistedPackStatus?

    init(state: PersistedPackStatus?) {
        self.state = state
    }

    func load() throws -> PersistedPackStatus? {
        lock.withLock { state }
    }

    func save(_ state: PersistedPackStatus) throws {
        lock.withLock { self.state = state }
    }
}

private final class FailingPackStatusURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var storedRequestCount = 0

    static var requestCount: Int {
        lock.withLock { storedRequestCount }
    }

    static func reset() {
        lock.withLock { storedRequestCount = 0 }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.withLock { Self.storedRequestCount += 1 }
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}
