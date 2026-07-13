import AICCore
import Foundation
import Security

protocol PackStatusAuthorizing: Sendable {
    func authorize(packAt url: URL, refresh: Bool) async throws
}

enum PackStatusGateError: Error, Equatable, LocalizedError {
    case invalidConfiguration
    case statusUnavailable
    case packNotListed
    case withdrawn(reasonCode: String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            "AIC's data-pack status service is not configured correctly. Scanning is paused."
        case .statusUnavailable:
            "AIC could not verify the current data-pack status. Connect to the internet and try again."
        case .packNotListed:
            "This data pack is not present in the verified status catalog. Update AIC before scanning."
        case .withdrawn:
            "Scanning is paused because this historical data pack was withdrawn after a quality review. Update AIC before scanning."
        }
    }
}

private struct PersistedPackStatus: Codable, Equatable {
    let envelopeData: Data
    let checkpoint: PackStatusCheckpoint
    let verifiedWallClockUnix: TimeInterval
    let verifiedSystemUptime: TimeInterval
    let verifiedBootTimeUnix: TimeInterval
}

private enum PackStatusStoreError: Error {
    case unexpectedStatus(OSStatus)
}

private struct PackStatusStateStore: Sendable {
    private let service = "com.binhnguyenhealth.aic.pack-status"
    private let account = "global-v1"

    func load() throws -> PersistedPackStatus? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw PackStatusStoreError.unexpectedStatus(status)
        }
        return try JSONDecoder().decode(PersistedPackStatus.self, from: data)
    }

    func save(_ state: PersistedPackStatus) throws {
        let data = try JSONEncoder().encode(state)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addition = query
            attributes.forEach { addition[$0.key] = $0.value }
            let addStatus = SecItemAdd(addition as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw PackStatusStoreError.unexpectedStatus(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw PackStatusStoreError.unexpectedStatus(updateStatus)
        }
    }
}

actor PackStatusClient: PackStatusAuthorizing {
    static let shared = PackStatusClient()

    private static let refreshInterval: TimeInterval = 15 * 60
    private static let endpointInfoKey = "AIC_PACK_STATUS_URL"
    private static let bootstrapName = "pack_status_bootstrap"

    private let endpointURL: URL?
    private let bootstrapData: Data?
    private let verifier: PackStatusVerifier
    private let stateStore: PackStatusStateStore
    private let session: URLSession
    private var loadedState = false
    private var state: PersistedPackStatus?
    private var lastRefreshAttempt: Date?
    private var packHashes: [URL: String] = [:]

    init(bundle: Bundle = .main) {
        endpointURL = Self.validEndpoint(
            bundle.object(forInfoDictionaryKey: Self.endpointInfoKey) as? String
        )
        bootstrapData = bundle.url(
            forResource: Self.bootstrapName,
            withExtension: "json"
        ).flatMap { try? Data(contentsOf: $0) }
        verifier = PackStatusVerifier(trustAnchor: Self.trustAnchor)
        stateStore = PackStatusStateStore()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 15
        session = URLSession(configuration: configuration)
    }

    func authorize(packAt url: URL, refresh: Bool) async throws {
        let packSHA = try cachedPackSHA(for: url)
        try loadStateIfNeeded()

        if state?.checkpoint.withdrawnPackSHA256.contains(packSHA) == true {
            throw PackStatusGateError.withdrawn(reasonCode: "previously-verified")
        }

        if refresh, shouldRefresh() {
            lastRefreshAttempt = Date()
            do {
                try await refreshFromNetwork(forPackSHA: packSHA)
            } catch let error as PackStatusGateError {
                switch error {
                case .withdrawn, .packNotListed:
                    throw error
                case .invalidConfiguration, .statusUnavailable:
                    break
                }
            } catch is PackStatusStoreError {
                throw PackStatusGateError.statusUnavailable
            } catch {
                // A network, signature, expiry, rollback, or CDN error never
                // replaces a still-valid cached status.
            }
        }

        if state == nil {
            try acceptBootstrap(forPackSHA: packSHA)
        }
        guard let state else { throw PackStatusGateError.statusUnavailable }
        if state.checkpoint.withdrawnPackSHA256.contains(packSHA) {
            throw PackStatusGateError.withdrawn(reasonCode: "previously-verified")
        }

        let now = Date()
        let verified: VerifiedPackStatus
        do {
            verified = try verifier.verify(
                envelopeData: state.envelopeData,
                previous: state.checkpoint,
                now: now,
                trustedTimeFloor: trustedTimeFloor(for: state, now: now)
            )
        } catch let error as PackStatusVerificationError {
            throw error
        } catch {
            throw PackStatusGateError.statusUnavailable
        }
        try requireActive(verified, packSHA: packSHA)
    }

    static func statusRequest(url: URL) -> URLRequest {
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 12
        )
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func loadStateIfNeeded() throws {
        guard !loadedState else { return }
        state = try stateStore.load()
        loadedState = true
    }

    private func shouldRefresh(now: Date = Date()) -> Bool {
        guard endpointURL != nil else { return false }
        guard let lastRefreshAttempt else { return true }
        return now.timeIntervalSince(lastRefreshAttempt) >= Self.refreshInterval
    }

    private func refreshFromNetwork(forPackSHA packSHA: String) async throws {
        guard let endpointURL else { throw PackStatusGateError.invalidConfiguration }
        let (data, response) = try await session.data(for: Self.statusRequest(url: endpointURL))
        guard data.count <= PackStatusVerifier.maximumEnvelopeBytes,
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              http.url == endpointURL else {
            throw PackStatusGateError.statusUnavailable
        }
        let wallClock = Date()
        let serverDate = Self.httpDate(http.value(forHTTPHeaderField: "Date"))
        let verificationNow = max(wallClock, serverDate ?? .distantPast)
        let verified = try verifier.verify(
            envelopeData: data,
            previous: state?.checkpoint,
            now: verificationNow,
            trustedTimeFloor: state.map { trustedTimeFloor(for: $0, now: wallClock) }
        )
        let gateError = statusError(verified, packSHA: packSHA)
        do {
            try persist(verified, packSHA: packSHA, observedAt: verificationNow)
        } catch {
            // Receiving a valid withdrawal or omission always fails closed,
            // even if protected persistence is temporarily unavailable.
            if let gateError { throw gateError }
            throw error
        }
        if let gateError { throw gateError }
    }

    private func acceptBootstrap(forPackSHA packSHA: String) throws {
        guard let bootstrapData else { throw PackStatusGateError.invalidConfiguration }
        let now = Date()
        let verified = try verifier.verify(envelopeData: bootstrapData, now: now)
        try persist(verified, packSHA: packSHA, observedAt: now)
    }

    private func persist(
        _ verified: VerifiedPackStatus,
        packSHA: String,
        observedAt: Date
    ) throws {
        let uptime = ProcessInfo.processInfo.systemUptime
        let newState = PersistedPackStatus(
            envelopeData: verified.envelopeData,
            checkpoint: verified.checkpoint(
                forPackSHA256: packSHA,
                previous: state?.checkpoint
            ),
            verifiedWallClockUnix: observedAt.timeIntervalSince1970,
            verifiedSystemUptime: uptime,
            verifiedBootTimeUnix: observedAt.timeIntervalSince1970 - uptime
        )
        // Persistence happens before the status is acted on. If Keychain is not
        // available, scanning fails rather than accepting an unpersisted state.
        try stateStore.save(newState)
        state = newState
    }

    private func requireActive(_ verified: VerifiedPackStatus, packSHA: String) throws {
        if let error = statusError(verified, packSHA: packSHA) { throw error }
    }

    private func statusError(
        _ verified: VerifiedPackStatus,
        packSHA: String
    ) -> PackStatusGateError? {
        guard let entry = verified.entry(forPackSHA256: packSHA) else { return .packNotListed }
        guard entry.status == .withdrawn else { return nil }
        return .withdrawn(reasonCode: entry.reasonCode ?? "quality-review")
    }

    private func cachedPackSHA(for url: URL) throws -> String {
        if let cached = packHashes[url] { return cached }
        let digest = try PackStatusVerifier.sha256Hex(fileAt: url)
        packHashes[url] = digest
        return digest
    }

    private func trustedTimeFloor(for state: PersistedPackStatus, now: Date) -> Date {
        let uptime = ProcessInfo.processInfo.systemUptime
        let bootTime = now.timeIntervalSince1970 - uptime
        let sameBoot = abs(bootTime - state.verifiedBootTimeUnix) < 10 && uptime >= state.verifiedSystemUptime
        let floorUnix = sameBoot
            ? state.verifiedWallClockUnix + (uptime - state.verifiedSystemUptime)
            : state.verifiedWallClockUnix
        return Date(timeIntervalSince1970: floorUnix)
    }

    private static func validEndpoint(_ rawValue: String?) -> URL? {
        guard let rawValue,
              let url = URL(string: rawValue),
              url.scheme == "https",
              url.host != nil,
              url.user == nil,
              url.password == nil,
              url.query == nil,
              url.fragment == nil else { return nil }
        return url
    }

    private static func httpDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter.date(from: value)
    }

    static let trustAnchor = PackStatusTrustAnchor(
        threshold: 2,
        publicKeys: [
            "release-a": Data(base64Encoded: "7t4SjVkhc9sdaXwJLPT6CgMVnX2Hm2MYNymwT4Os3OU=")!,
            "release-b": Data(base64Encoded: "iP27LTb64jA7kCBHk/IQRW1CfoEhHCU6pj7uzDLucvs=")!,
            "release-c": Data(base64Encoded: "kF3zDDVT9191D7FIwTQ9YXvGER2RfWAQtEzIBSUnMkA=")!,
        ]
    )
}
