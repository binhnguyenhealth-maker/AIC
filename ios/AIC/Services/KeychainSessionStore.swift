#if !GUEST_ONLY_V1
import AICCore
import Foundation
import Security

enum KeychainStoreError: Error {
    case unexpectedStatus(OSStatus)
}

protocol SessionStoring {
    func load() throws -> AuthSession?
    func save(_ session: AuthSession) throws
    func delete() throws
}

struct KeychainSessionStore: SessionStoring {
    private let service = "com.binhnguyenhealth.aic.session"
    private let account = "active-session"

    func load() throws -> AuthSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
        return try JSONDecoder().decode(AuthSession.self, from: data)
    }

    func save(_ session: AuthSession) throws {
        let data = try JSONEncoder().encode(session)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addition = query
            attributes.forEach { addition[$0.key] = $0.value }
            let addStatus = SecItemAdd(addition as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainStoreError.unexpectedStatus(addStatus) }
        } else if updateStatus != errSecSuccess {
            throw KeychainStoreError.unexpectedStatus(updateStatus)
        }
    }

    func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
    }
}
#endif
