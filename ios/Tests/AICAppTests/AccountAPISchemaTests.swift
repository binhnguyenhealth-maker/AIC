#if !GUEST_ONLY_V1
import AICCore
import XCTest
@testable import AIC

final class AccountAPISchemaTests: XCTestCase {
    override func setUp() {
        super.setUp()
        RecordingURLProtocol.reset()
    }

    func testEveryAccountRequestUsesClosedLocationFreeJSON() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecordingURLProtocol.self]
        let api = AccountAPI(
            baseURL: URL(string: "https://api.aic.test")!,
            session: URLSession(configuration: configuration)
        )

        let session = try await api.exchangeAppleCredential(
            authorizationCode: "apple-code",
            identityToken: "apple-id-token",
            rawNonce: "nonce"
        )
        _ = try await api.suggestedUsername(accessToken: session.accessToken)
        _ = try await api.claimUsername("chi_tester", accessToken: session.accessToken)
        let proof = try await api.reauthenticateApple(
            authorizationCode: "new-code",
            identityToken: "new-token",
            rawNonce: "new-nonce",
            accessToken: session.accessToken
        )
        try await api.logout(accessToken: session.accessToken)
        try await api.deleteAccount(accessToken: session.accessToken, reauthToken: proof)

        let requests = RecordingURLProtocol.recordedRequests
        XCTAssertEqual(requests.count, 6)
        let forbidden = ["latitude", "longitude", "coordinate", "address", "route", "cell", "scan"]
        for request in requests {
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8)?.lowercased() ?? ""
            for term in forbidden {
                XCTAssertFalse(body.contains("\"\(term)"), "Forbidden field \(term) in \(request.url?.path ?? "request")")
            }
        }
    }
}

private final class RecordingURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var storage: [URLRequest] = []

    static var recordedRequests: [URLRequest] {
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

        let path = request.url?.path ?? ""
        let status: Int
        let body: Data
        switch path {
        case "/v1/auth/apple/exchange":
            status = 200
            body = Data(#"{"account":{"id":"account-1","username":null,"status":"active"},"accessToken":"access","accessTokenExpiresIn":900,"refreshToken":"refresh","refreshTokenExpiresIn":2592000}"#.utf8)
        case "/v1/usernames/suggest":
            status = 200
            body = Data(#"{"username":"chi_tester","available":true}"#.utf8)
        case "/v1/usernames/claim":
            status = 200
            body = Data(#"{"username":"chi_tester"}"#.utf8)
        case "/v1/auth/apple/reauth":
            status = 200
            body = Data(#"{"reauthToken":"proof","expiresIn":300}"#.utf8)
        default:
            status = 204
            body = Data()
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !body.isEmpty { client?.urlProtocol(self, didLoad: body) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
#endif
