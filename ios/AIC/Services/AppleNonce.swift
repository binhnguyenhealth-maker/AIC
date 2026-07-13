#if !GUEST_ONLY_V1
import CryptoKit
import Foundation
import Security

enum AppleNonce {
    static func make(length: Int = 32) throws -> String {
        precondition(length > 0)
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var random = [UInt8](repeating: 0, count: 16)
            let status = random.withUnsafeMutableBytes { buffer in
                SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
            }
            guard status == errSecSuccess else { throw KeychainStoreError.unexpectedStatus(status) }
            for value in random where remaining > 0 {
                if value < characters.count {
                    result.append(characters[Int(value)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
#endif
