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
}
