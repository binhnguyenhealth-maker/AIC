import AICCore
import Foundation

protocol AccountAPIProtocol {
    func exchangeAppleCredential(authorizationCode: String, identityToken: String, rawNonce: String) async throws -> AuthSession
    func refresh(_ current: AuthSession) async throws -> AuthSession
    func suggestedUsername(accessToken: String) async throws -> String
    func claimUsername(_ username: String, accessToken: String) async throws -> String
    func logout(accessToken: String) async throws
    func reauthenticateApple(
        authorizationCode: String,
        identityToken: String,
        rawNonce: String,
        accessToken: String
    ) async throws -> String
    func deleteAccount(accessToken: String, reauthToken: String) async throws
}

enum AccountAPIError: LocalizedError {
    case configuration
    case invalidResponse
    case server(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .configuration:
            "Account service setup is incomplete. Set AIC_API_BASE_URL to the production HTTPS endpoint."
        case .invalidResponse:
            "The account service returned an unreadable response."
        case let .server(_, message):
            message
        }
    }
}

private struct EmptyBody: Encodable {}

private struct AppleExchangeBody: Encodable {
    let authorizationCode: String
    let identityToken: String
    let rawNonce: String
}

private struct RefreshBody: Encodable {
    let refreshToken: String
}

private struct UsernameSuggestionBody: Encodable {
    let preferredBase: String?
}

private struct UsernameClaimBody: Encodable {
    let username: String
}

private struct ReauthResponse: Decodable {
    let reauthToken: String
    let expiresIn: TimeInterval
}

private struct DeleteAccountBody: Encodable {
    let confirmation = "DELETE"
    let reauthToken: String
}

private struct AccountEnvelope: Decodable {
    let account: RemoteAccount
    let accessToken: String
    let accessTokenExpiresIn: TimeInterval
    let refreshToken: String
    let refreshTokenExpiresIn: TimeInterval
}

private struct RemoteAccount: Decodable {
    let id: String
    let username: String?
    let status: String
}

private struct UsernameSuggestionResponse: Decodable {
    let username: String
    let available: Bool
}

private struct UsernameClaimResponse: Decodable {
    let username: String
}

private struct ErrorEnvelope: Decodable {
    struct Detail: Decodable {
        let code: String
        let message: String
        let requestId: String?
    }

    let error: Detail
}

actor AccountAPI: AccountAPIProtocol {
    private let session: URLSession
    private let baseURL: URL?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(bundle: Bundle = .main) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)

        let rawValue = bundle.object(forInfoDictionaryKey: "AIC_API_BASE_URL") as? String
        if let rawValue,
           let url = URL(string: rawValue),
           url.scheme == "https",
           url.host?.hasSuffix("example.invalid") == false {
            baseURL = url
        } else {
            baseURL = nil
        }
    }

    init(baseURL: URL?, session: URLSession) {
        if let baseURL,
           baseURL.scheme == "https" || baseURL.host == "127.0.0.1" || baseURL.host == "localhost" {
            self.baseURL = baseURL
        } else {
            self.baseURL = nil
        }
        self.session = session
    }

    func exchangeAppleCredential(
        authorizationCode: String,
        identityToken: String,
        rawNonce: String
    ) async throws -> AuthSession {
        let envelope: AccountEnvelope = try await send(
            path: "/v1/auth/apple/exchange",
            method: "POST",
            body: AppleExchangeBody(
                authorizationCode: authorizationCode,
                identityToken: identityToken,
                rawNonce: rawNonce
            )
        )
        return session(from: envelope)
    }

    func refresh(_ current: AuthSession) async throws -> AuthSession {
        let envelope: AccountEnvelope = try await send(
            path: "/v1/auth/refresh",
            method: "POST",
            body: RefreshBody(refreshToken: current.refreshToken)
        )
        return session(from: envelope)
    }

    func suggestedUsername(accessToken: String) async throws -> String {
        let response: UsernameSuggestionResponse = try await send(
            path: "/v1/usernames/suggest",
            method: "POST",
            bearerToken: accessToken,
            body: UsernameSuggestionBody(preferredBase: nil)
        )
        guard response.available else {
            throw AccountAPIError.server(status: 409, message: "Please request another username suggestion.")
        }
        return response.username
    }

    func claimUsername(_ username: String, accessToken: String) async throws -> String {
        let response: UsernameClaimResponse = try await send(
            path: "/v1/usernames/claim",
            method: "PUT",
            bearerToken: accessToken,
            body: UsernameClaimBody(username: username)
        )
        return response.username
    }

    func logout(accessToken: String) async throws {
        try await sendWithoutResponse(
            path: "/v1/auth/logout",
            method: "POST",
            bearerToken: accessToken,
            body: EmptyBody()
        )
    }

    func reauthenticateApple(
        authorizationCode: String,
        identityToken: String,
        rawNonce: String,
        accessToken: String
    ) async throws -> String {
        let response: ReauthResponse = try await send(
            path: "/v1/auth/apple/reauth",
            method: "POST",
            bearerToken: accessToken,
            body: AppleExchangeBody(
                authorizationCode: authorizationCode,
                identityToken: identityToken,
                rawNonce: rawNonce
            )
        )
        guard !response.reauthToken.isEmpty, response.expiresIn > 0 else {
            throw AccountAPIError.invalidResponse
        }
        return response.reauthToken
    }

    func deleteAccount(accessToken: String, reauthToken: String) async throws {
        try await sendWithoutResponse(
            path: "/v1/account",
            method: "DELETE",
            bearerToken: accessToken,
            body: DeleteAccountBody(reauthToken: reauthToken)
        )
    }

    private func session(from envelope: AccountEnvelope) -> AuthSession {
        AuthSession(
            accountID: envelope.account.id,
            accessToken: envelope.accessToken,
            refreshToken: envelope.refreshToken,
            accessTokenExpiresAt: Date().addingTimeInterval(envelope.accessTokenExpiresIn),
            username: envelope.account.username
        )
    }

    private func send<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        bearerToken: String? = nil,
        body: Body
    ) async throws -> Response {
        let request = try makeRequest(path: path, method: method, bearerToken: bearerToken, body: body)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw AccountAPIError.invalidResponse
        }
    }

    private func sendWithoutResponse<Body: Encodable>(
        path: String,
        method: String,
        bearerToken: String,
        body: Body
    ) async throws {
        let request = try makeRequest(path: path, method: method, bearerToken: bearerToken, body: body)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
    }

    private func makeRequest<Body: Encodable>(
        path: String,
        method: String,
        bearerToken: String?,
        body: Body
    ) throws -> URLRequest {
        guard let baseURL, let url = URL(string: path, relativeTo: baseURL) else {
            throw AccountAPIError.configuration
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try encoder.encode(body)
        return request
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AccountAPIError.invalidResponse
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let message = (try? decoder.decode(ErrorEnvelope.self, from: data).error.message)
                ?? "The account service could not complete this request."
            throw AccountAPIError.server(status: httpResponse.statusCode, message: message)
        }
    }
}
