import Foundation

public enum UsernameValidation: Equatable, Sendable {
    case valid(normalized: String)
    case invalid(message: String)
}

public enum UsernamePolicy {
    public static let minimumLength = 3
    public static let maximumLength = 20

    private static let reserved: Set<String> = [
        "admin", "administrator", "aic", "amicooked", "apple", "help", "official",
        "privacy", "root", "security", "staff", "support", "system"
    ]

    public static func normalize(_ candidate: String) -> String {
        candidate
            .precomposedStringWithCompatibilityMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
    }

    public static func validate(_ candidate: String) -> UsernameValidation {
        let normalized = normalize(candidate)
        guard (minimumLength ... maximumLength).contains(normalized.count) else {
            return .invalid(message: "Use 3–20 characters.")
        }
        guard normalized.unicodeScalars.allSatisfy({
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_").contains($0)
        }) else {
            return .invalid(message: "Use lowercase letters, numbers, and underscores only.")
        }
        guard !reserved.contains(normalized) else {
            return .invalid(message: "That username is reserved.")
        }
        guard normalized.first != "_", normalized.last != "_" else {
            return .invalid(message: "A username cannot start or end with an underscore.")
        }
        return .valid(normalized: normalized)
    }
}
