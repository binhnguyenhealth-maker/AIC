import AICCore
import XCTest
@testable import AIC

@MainActor
final class AccountDeletionTests: XCTestCase {
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
        XCTAssertEqual(model.phase, .signedOut)
        XCTAssertNil(model.session)
        XCTAssertNil(store.session)
        XCTAssertEqual(api.reauthenticationCount, 1)
        XCTAssertEqual(api.deletionCount, 1)
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
    var reauthenticationCount = 0
    var deletionCount = 0

    init(session: AuthSession) { self.session = session }

    func exchangeAppleCredential(authorizationCode: String, identityToken: String, rawNonce: String) async throws -> AuthSession { session }
    func refresh(_ current: AuthSession) async throws -> AuthSession { current }
    func suggestedUsername(accessToken: String) async throws -> String { "chi_tester" }
    func claimUsername(_ username: String, accessToken: String) async throws -> String { username }
    func logout(accessToken: String) async throws {}

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
