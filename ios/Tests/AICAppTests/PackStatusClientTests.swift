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
            now: Date(timeIntervalSince1970: 1_783_910_000)
        )
        let packSHA = try PackStatusVerifier.sha256Hex(fileAt: packURL)

        XCTAssertEqual(packSHA, "821130a16d616c808c795844623c9a134120719685b4ae59303394bcfe8d01e7")
        XCTAssertEqual(verified.entry(forPackSHA256: packSHA)?.status, .active)
        XCTAssertEqual(verified.payload.sequence, 1)
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
        XCTAssertFalse(request.url!.absoluteString.contains("821130"))
    }
}
