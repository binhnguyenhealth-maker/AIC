import CoreLocation
import XCTest
@testable import AIC

final class PrivacyConfigurationTests: XCTestCase {
    func testAppRequestsForegroundLocationOnly() {
        let info = Bundle.main.infoDictionary ?? [:]
        XCTAssertNotNil(info["NSLocationWhenInUseUsageDescription"])
        XCTAssertNil(info["NSLocationAlwaysUsageDescription"])
        XCTAssertNil(info["NSLocationAlwaysAndWhenInUseUsageDescription"])
        let backgroundModes = info["UIBackgroundModes"] as? [String] ?? []
        XCTAssertFalse(backgroundModes.contains("location"))
    }

    func testSignInWithAppleEntitlementIsPresent() throws {
        let iosRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let entitlementsURL = iosRoot.appendingPathComponent("AIC/Config/AIC.entitlements")
        let data = try Data(contentsOf: entitlementsURL)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any])
        XCTAssertEqual(plist["com.apple.developer.applesignin"] as? [String], ["Default"])

        let project = try String(contentsOf: iosRoot.appendingPathComponent("AIC.xcodeproj/project.pbxproj"))
        XCTAssertTrue(project.contains("com.apple.SignInWithApple.iOS"))
    }

    func testPublicPolicyURLsAreHTTPS() throws {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, "Am I Cooked?")
        for key in [
            "AIC_PRIVACY_URL", "AIC_SUPPORT_URL", "AIC_TERMS_URL",
            "AIC_METHODOLOGY_URL", "AIC_ACCOUNT_DELETION_URL"
        ] {
            let raw = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: key) as? String)
            XCTAssertEqual(URL(string: raw)?.scheme, "https", key)
        }
    }

    @MainActor
    func testPermissionDenialAndRestrictionOfferManualFallback() {
        XCTAssertTrue(LocationService.offersManualFallback(for: .denied))
        XCTAssertTrue(LocationService.offersManualFallback(for: .restricted))
        XCTAssertTrue(LocationService.offersManualFallback(for: .failed("test")))
        XCTAssertFalse(LocationService.offersManualFallback(for: .locating))
    }
}
