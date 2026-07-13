import AICCore
#if !GUEST_ONLY_V1
import AuthenticationServices
#endif
import Foundation

#if DEBUG
enum ShowcaseData {
    enum Screen: String {
        case home
        case result
        case receipt
        case settings
        case passport
    }

    static var requestedScreen: Screen? {
        let argumentValue = ProcessInfo.processInfo.arguments
            .first { $0.hasPrefix("--aic-showcase=") }?
            .replacingOccurrences(of: "--aic-showcase=", with: "")
        guard let value = argumentValue ?? ProcessInfo.processInfo.environment["AIC_SHOWCASE_SCREEN"] else { return nil }
        return Screen(rawValue: value)
    }

#if !GUEST_ONLY_V1
    static let session = AuthSession(
        accountID: "showcase",
        accessToken: "showcase",
        refreshToken: "showcase",
        accessTokenExpiresAt: .distantFuture,
        username: nil
    )
#endif

    static let result = ChicagoScanResult(
        cookedScore: 75,
        chicagoPercentile: 76,
        estimatedIncidentCount: 135,
        categoryCounts: [
            CategoryCount(category: .assaultBattery, count: 40),
            CategoryCount(category: .robbery, count: 15),
            CategoryCount(category: .theft, count: 65),
            CategoryCount(category: .motorVehicleTheft, count: 15),
        ],
        neighborhood: "Near West Side",
        sourceThroughDate: "2026-06-30",
        periodStart: "2025-07-01",
        methodologyVersion: "beta-cell250-q5-area-v3"
    )

    static let freshness = PackFreshnessSummary(
        sourceThroughDate: "2026-06-30",
        periodStart: "2025-07-01",
        sourceRetrievedAt: Date(timeIntervalSince1970: 1_783_909_883),
        freshUntilDate: "2026-08-07",
        expiresAtDate: "2026-08-29",
        state: .withinUpdateWindow,
        daysSinceSourceThrough: 13,
        daysUntilCutoff: 25
    )
}
#endif

#if !GUEST_ONLY_V1
struct AppleCredentialMaterial: Equatable {
    let authorizationCode: String
    let identityToken: String
    let rawNonce: String
}
#endif

@MainActor
final class AppModel: ObservableObject {
    enum Phase: Equatable {
        case launching
        case guest
#if !GUEST_ONLY_V1
        case signedOut
        case needsUsername
        case ready
#endif
    }

    @Published private(set) var phase: Phase = .launching
#if !GUEST_ONLY_V1
    @Published private(set) var session: AuthSession?
    @Published var usernameDraft = ""
#endif
    @Published var measurementPreference: AICMeasurementPreference {
        didSet {
            userDefaults.set(measurementPreference.rawValue, forKey: Self.measurementPreferenceKey)
        }
    }
#if !GUEST_ONLY_V1
    @Published var isBusy = false
#endif
    @Published var presentedError: String?

#if !GUEST_ONLY_V1
    private let accountAPI: any AccountAPIProtocol
    private let sessionStore: any SessionStoring
#endif
    private let userDefaults: UserDefaults
    private static let measurementPreferenceKey = "aic.measurement-preference"

#if GUEST_ONLY_V1
    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        measurementPreference = userDefaults.string(forKey: Self.measurementPreferenceKey)
            .flatMap(AICMeasurementPreference.init(rawValue:)) ?? .automatic
    }
#else
    init(
        accountAPI: any AccountAPIProtocol = AccountAPI(),
        sessionStore: any SessionStoring = KeychainSessionStore(),
        userDefaults: UserDefaults = .standard
    ) {
        self.accountAPI = accountAPI
        self.sessionStore = sessionStore
        self.userDefaults = userDefaults
        measurementPreference = userDefaults.string(forKey: Self.measurementPreferenceKey)
            .flatMap(AICMeasurementPreference.init(rawValue:)) ?? .automatic
#if DEBUG
        if ShowcaseData.requestedScreen != nil {
            session = ShowcaseData.session
            phase = .ready
        }
#endif
    }
#endif

#if !GUEST_ONLY_V1
    var username: String { session?.username ?? "" }
    var isSignedIn: Bool { session != nil }
#endif
    var distanceSystem: AICDistanceSystem { measurementPreference.resolvedSystem() }

#if GUEST_ONLY_V1
    func prepare() {
        guard phase == .launching else { return }
        phase = .guest
    }
#else
    func restoreSession() async {
        guard phase == .launching else { return }
        do {
            guard var restored = try sessionStore.load() else {
                phase = .guest
                return
            }
            if restored.accessTokenExpiresAt <= Date().addingTimeInterval(60) {
                restored = try await accountAPI.refresh(restored)
                try sessionStore.save(restored)
            }
            session = restored
            if let username = restored.username, !username.isEmpty {
                phase = .ready
            } else {
                phase = .needsUsername
                await requestUsernameSuggestion()
            }
        } catch {
            try? sessionStore.delete()
            session = nil
            phase = .guest
        }
    }

    func continueWithoutAccount() {
        session = nil
        usernameDraft = ""
        phase = .guest
    }

    func startSignIn() {
        phase = .signedOut
    }

    func completeAppleAuthorization(_ authorization: ASAuthorization, rawNonce: String) async {
        guard let material = credentialMaterial(from: authorization, rawNonce: rawNonce) else {
            presentedError = "Apple did not return the credentials required to create this account. Please try again."
            return
        }

        await completeAppleCredential(material)
    }

    func completeAppleCredential(_ material: AppleCredentialMaterial) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let newSession = try await accountAPI.exchangeAppleCredential(
                authorizationCode: material.authorizationCode,
                identityToken: material.identityToken,
                rawNonce: material.rawNonce
            )
            try sessionStore.save(newSession)
            session = newSession
            if let username = newSession.username, !username.isEmpty {
                phase = .ready
            } else {
                phase = .needsUsername
                await requestUsernameSuggestion()
            }
        } catch {
            presentedError = error.localizedDescription
        }
    }

    func handleAppleAuthorizationFailure(_ error: Error) {
        if let authorizationError = error as? ASAuthorizationError, authorizationError.code == .canceled {
            return
        }
        presentedError = "Sign in with Apple did not complete. \(error.localizedDescription)"
    }

    func requestUsernameSuggestion() async {
        guard let session else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            usernameDraft = try await accountAPI.suggestedUsername(accessToken: session.accessToken)
        } catch {
            presentedError = error.localizedDescription
        }
    }

    func claimUsername() async {
        guard let session else { return }
        guard case let .valid(normalized) = UsernamePolicy.validate(usernameDraft) else {
            if case let .invalid(message) = UsernamePolicy.validate(usernameDraft) {
                presentedError = message
            }
            return
        }

        isBusy = true
        defer { isBusy = false }
        do {
            let claimed = try await accountAPI.claimUsername(normalized, accessToken: session.accessToken)
            let updated = AuthSession(
                accountID: session.accountID,
                accessToken: session.accessToken,
                refreshToken: session.refreshToken,
                accessTokenExpiresAt: session.accessTokenExpiresAt,
                username: claimed
            )
            try sessionStore.save(updated)
            self.session = updated
            phase = .ready
        } catch {
            presentedError = error.localizedDescription
        }
    }

    func logout() async {
        guard let session else { return }
        isBusy = true
        do {
            try await accountAPI.logout(accessToken: session.accessToken)
        } catch {
            // Local logout still removes the credential. The short-lived access token expires server-side.
        }
        try? sessionStore.delete()
        self.session = nil
        usernameDraft = ""
        phase = .guest
        isBusy = false
    }

    func deleteAccount(after authorization: ASAuthorization, rawNonce: String) async -> Bool {
        guard let material = credentialMaterial(from: authorization, rawNonce: rawNonce) else {
            presentedError = "Apple did not return the proof required to delete this account. Please try again."
            return false
        }
        return await deleteAccount(using: material)
    }

    func deleteAccount(using material: AppleCredentialMaterial) async -> Bool {
        guard let session else { return false }
        isBusy = true
        defer { isBusy = false }
        do {
            let reauthToken = try await accountAPI.reauthenticateApple(
                authorizationCode: material.authorizationCode,
                identityToken: material.identityToken,
                rawNonce: material.rawNonce,
                accessToken: session.accessToken
            )
            try await accountAPI.deleteAccount(accessToken: session.accessToken, reauthToken: reauthToken)
            try? sessionStore.delete()
            ReceiptArtifactStore.removeAllTemporaryReceipts()
            self.session = nil
            usernameDraft = ""
            phase = .guest
            return true
        } catch {
            presentedError = error.localizedDescription
            return false
        }
    }

    private func credentialString(from data: Data) -> String? {
        guard let string = String(data: data, encoding: .utf8), !string.isEmpty else { return nil }
        return string
    }

    private func credentialMaterial(from authorization: ASAuthorization, rawNonce: String) -> AppleCredentialMaterial? {
        guard !rawNonce.isEmpty,
              let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let authorizationCodeData = credential.authorizationCode,
              let identityToken = credentialString(from: tokenData),
              let authorizationCode = credentialString(from: authorizationCodeData) else {
            return nil
        }
        return AppleCredentialMaterial(
            authorizationCode: authorizationCode,
            identityToken: identityToken,
            rawNonce: rawNonce
        )
    }
#endif

    func present(_ message: String) {
        presentedError = message
    }
}
