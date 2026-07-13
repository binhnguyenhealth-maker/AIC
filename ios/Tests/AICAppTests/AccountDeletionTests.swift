import AICCore
import XCTest
@testable import AIC

@MainActor
final class AccountDeletionTests: XCTestCase {
    func testMissingSessionEntersGuestModeWithoutAccount() async {
        let api = FakeAccountAPI(session: .fixture)
        let store = FakeSessionStore(session: nil)
        let model = AppModel(accountAPI: api, sessionStore: store)

        await model.restoreSession()

        XCTAssertEqual(model.phase, .guest)
        XCTAssertNil(model.session)
        XCTAssertFalse(model.isSignedIn)
        XCTAssertEqual(api.refreshCount, 0)
    }

    func testGuestCanChooseOptionalSignInAndReturnToGuestMode() async {
        let model = AppModel(
            accountAPI: FakeAccountAPI(session: .fixture),
            sessionStore: FakeSessionStore(session: nil)
        )
        await model.restoreSession()

        model.startSignIn()
        XCTAssertEqual(model.phase, .signedOut)

        model.continueWithoutAccount()
        XCTAssertEqual(model.phase, .guest)
    }

    func testLogoutReturnsToGuestModeAndClearsStoredSession() async {
        let api = FakeAccountAPI(session: .fixture)
        let store = FakeSessionStore(session: .fixture)
        let model = AppModel(accountAPI: api, sessionStore: store)
        await model.restoreSession()

        await model.logout()

        XCTAssertEqual(model.phase, .guest)
        XCTAssertNil(model.session)
        XCTAssertNil(store.session)
        XCTAssertEqual(api.logoutCount, 1)
    }

    func testMeasurementPreferencePersistsLocally() {
        let suiteName = "AICMeasurementPreferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let firstModel = AppModel(
            accountAPI: FakeAccountAPI(session: .fixture),
            sessionStore: FakeSessionStore(session: nil),
            userDefaults: defaults
        )

        firstModel.measurementPreference = .metric

        let restoredModel = AppModel(
            accountAPI: FakeAccountAPI(session: .fixture),
            sessionStore: FakeSessionStore(session: nil),
            userDefaults: defaults
        )
        XCTAssertEqual(restoredModel.measurementPreference, .metric)
    }

    func testServerConfirmedDeletionAlwaysClearsLocalSession() async {
        let session = AuthSession(
            accountID: "account-1",
            accessToken: "access-secret",
            refreshToken: "refresh-secret",
            accessTokenExpiresAt: Date().addingTimeInterval(900),
            username: "chi_tester"
        )
        let api = FakeAccountAPI(session: session)
        let store = FakeSessionStore(session: session)
        let model = AppModel(accountAPI: api, sessionStore: store)
        await model.restoreSession()

        let deleted = await model.deleteAccount(using: AppleCredentialMaterial(
            authorizationCode: "apple-code",
            identityToken: "apple-token",
            rawNonce: "nonce"
        ))

        XCTAssertTrue(deleted)
        XCTAssertEqual(model.phase, .guest)
        XCTAssertNil(model.session)
        XCTAssertNil(store.session)
        XCTAssertEqual(api.reauthenticationCount, 1)
        XCTAssertEqual(api.deletionCount, 1)
    }
}

private extension AuthSession {
    static var fixture: AuthSession {
        AuthSession(
            accountID: "account-1",
            accessToken: "access-secret",
            refreshToken: "refresh-secret",
            accessTokenExpiresAt: Date().addingTimeInterval(900),
            username: "chi_tester"
        )
    }
}

private final class FakeSessionStore: SessionStoring {
    var session: AuthSession?

    init(session: AuthSession?) { self.session = session }
    func load() throws -> AuthSession? { session }
    func save(_ session: AuthSession) throws { self.session = session }
    func delete() throws { session = nil }
}

private final class FakeAccountAPI: AccountAPIProtocol {
    let session: AuthSession
    var refreshCount = 0
    var logoutCount = 0
    var reauthenticationCount = 0
    var deletionCount = 0

    init(session: AuthSession) { self.session = session }

    func exchangeAppleCredential(authorizationCode: String, identityToken: String, rawNonce: String) async throws -> AuthSession { session }
    func refresh(_ current: AuthSession) async throws -> AuthSession {
        refreshCount += 1
        return current
    }
    func suggestedUsername(accessToken: String) async throws -> String { "chi_tester" }
    func claimUsername(_ username: String, accessToken: String) async throws -> String { username }
    func logout(accessToken: String) async throws { logoutCount += 1 }

    func reauthenticateApple(
        authorizationCode: String,
        identityToken: String,
        rawNonce: String,
        accessToken: String
    ) async throws -> String {
        reauthenticationCount += 1
        return "reauth-proof"
    }

    func deleteAccount(accessToken: String, reauthToken: String) async throws {
        XCTAssertEqual(reauthToken, "reauth-proof")
        deletionCount += 1
    }
}
