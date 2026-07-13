#if !GUEST_ONLY_V1
import XCTest
@testable import AICCore

final class UsernamePolicyTests: XCTestCase {
    func testNormalizesNFKCCaseAndAtSign() {
        XCTAssertEqual(UsernamePolicy.normalize(" @ＣＯＯＫＥＤ_7 "), "cooked_7")
    }

    func testAllowsOnlyBoundedASCIIHandle() {
        XCTAssertEqual(UsernamePolicy.validate("chi_cooked7"), .valid(normalized: "chi_cooked7"))
        XCTAssertEqual(UsernamePolicy.validate("ab"), .invalid(message: "Use 3–20 characters."))
        XCTAssertEqual(
            UsernamePolicy.validate("chicagó"),
            .invalid(message: "Use lowercase letters, numbers, and underscores only.")
        )
        XCTAssertEqual(UsernamePolicy.validate("support"), .invalid(message: "That username is reserved."))
    }
}
#endif
