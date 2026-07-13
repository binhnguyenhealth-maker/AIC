import AICCore
import Foundation

enum StatusValidationError: Error, LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case let .failed(message): message
        }
    }
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw StatusValidationError.failed(message) }
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 3 else {
    throw StatusValidationError.failed(
        "usage: AICPackStatusValidation PACK BOOTSTRAP PUBLIC_STATUS"
    )
}
let packURL = URL(fileURLWithPath: arguments[0])
let bootstrapURL = URL(fileURLWithPath: arguments[1])
let publicStatusURL = URL(fileURLWithPath: arguments[2])
let bootstrap = try Data(contentsOf: bootstrapURL)
let publicStatus = try Data(contentsOf: publicStatusURL)
try require(bootstrap == publicStatus, "bundled bootstrap and public status artifact differ")

let verifier = PackStatusVerifier(trustAnchor: PackStatusTrustAnchor(
    threshold: 2,
    publicKeys: [
        "release-a": Data(base64Encoded: "7t4SjVkhc9sdaXwJLPT6CgMVnX2Hm2MYNymwT4Os3OU=")!,
        "release-b": Data(base64Encoded: "iP27LTb64jA7kCBHk/IQRW1CfoEhHCU6pj7uzDLucvs=")!,
        "release-c": Data(base64Encoded: "kF3zDDVT9191D7FIwTQ9YXvGER2RfWAQtEzIBSUnMkA=")!,
    ]
))
let now = Date()
let verified = try verifier.verify(envelopeData: publicStatus, now: now)
let packSHA = try PackStatusVerifier.sha256Hex(fileAt: packURL)
try require(
    packSHA == "1a18629fa3429eefec10d0d025c80102ce7c48a63457e601c1c404001686ca32",
    "bundled pack hash changed without a new status issuance"
)
try require(
    verified.entry(forPackSHA256: packSHA)?.status == .active,
    "bundled pack is not active in the signed public status"
)
let expiresAt = Date(timeIntervalSince1970: TimeInterval(verified.payload.expiresAtUnix))
try require(
    expiresAt.timeIntervalSince(now) >= 24 * 60 * 60,
    "signed status has less than 24 hours remaining; issue a higher sequence before release"
)

let formatter = ISO8601DateFormatter()
print("AIC_PACK_STATUS_VALIDATION_OK")
print("sequence=\(verified.payload.sequence)")
print("pack_sha256=\(packSHA)")
print("expires_at=\(formatter.string(from: expiresAt))")
