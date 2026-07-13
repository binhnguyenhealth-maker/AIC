import CryptoKit
import Foundation

public enum PackRegistryStatus: String, Codable, Equatable, Sendable {
    case active
    case withdrawn
}

public struct PackStatusEntry: Codable, Equatable, Sendable {
    public let sha256: String
    public let status: PackRegistryStatus
    public let reasonCode: String?

    public init(sha256: String, status: PackRegistryStatus, reasonCode: String? = nil) {
        self.sha256 = sha256
        self.status = status
        self.reasonCode = reasonCode
    }
}

public struct PackStatusPayload: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let sequence: UInt64
    public let issuedAtUnix: Int64
    public let expiresAtUnix: Int64
    public let packs: [PackStatusEntry]

    public init(
        schemaVersion: Int,
        sequence: UInt64,
        issuedAtUnix: Int64,
        expiresAtUnix: Int64,
        packs: [PackStatusEntry]
    ) {
        self.schemaVersion = schemaVersion
        self.sequence = sequence
        self.issuedAtUnix = issuedAtUnix
        self.expiresAtUnix = expiresAtUnix
        self.packs = packs
    }
}

public struct PackStatusSignature: Codable, Equatable, Sendable {
    public let keyID: String
    public let signature: String

    public init(keyID: String, signature: String) {
        self.keyID = keyID
        self.signature = signature
    }
}

public struct SignedPackStatusEnvelope: Codable, Equatable, Sendable {
    /// Base64 of the exact UTF-8 JSON bytes signed by the release keys. Signing
    /// bytes rather than re-encoded JSON avoids ambiguous canonicalization.
    public let payload: String
    public let signatures: [PackStatusSignature]

    public init(payload: String, signatures: [PackStatusSignature]) {
        self.payload = payload
        self.signatures = signatures
    }
}

public struct PackStatusTrustAnchor: Equatable, Sendable {
    public let threshold: Int
    public let publicKeys: [String: Data]

    public init(threshold: Int, publicKeys: [String: Data]) {
        self.threshold = threshold
        self.publicKeys = publicKeys
    }
}

public struct PackStatusCheckpoint: Codable, Equatable, Sendable {
    public let sequence: UInt64
    public let payloadSHA256: String
    public let packSHA256: String
    public let packStatus: PackRegistryStatus?
    public let withdrawnPackSHA256: [String]

    public init(
        sequence: UInt64,
        payloadSHA256: String,
        packSHA256: String,
        packStatus: PackRegistryStatus?,
        withdrawnPackSHA256: [String] = []
    ) {
        self.sequence = sequence
        self.payloadSHA256 = payloadSHA256
        self.packSHA256 = packSHA256
        self.packStatus = packStatus
        self.withdrawnPackSHA256 = withdrawnPackSHA256
    }
}

public struct VerifiedPackStatus: Equatable, Sendable {
    public let payload: PackStatusPayload
    public let payloadSHA256: String
    public let envelopeData: Data

    public init(payload: PackStatusPayload, payloadSHA256: String, envelopeData: Data) {
        self.payload = payload
        self.payloadSHA256 = payloadSHA256
        self.envelopeData = envelopeData
    }

    public func entry(forPackSHA256 packSHA256: String) -> PackStatusEntry? {
        payload.packs.first { $0.sha256 == packSHA256 }
    }

    public func checkpoint(
        forPackSHA256 packSHA256: String,
        previous: PackStatusCheckpoint? = nil
    ) -> PackStatusCheckpoint {
        let newlyWithdrawn = payload.packs
            .filter { $0.status == .withdrawn }
            .map(\.sha256)
        let terminalWithdrawals = Array(Set(
            (previous?.withdrawnPackSHA256 ?? []) + newlyWithdrawn
        )).sorted()
        return PackStatusCheckpoint(
            sequence: payload.sequence,
            payloadSHA256: payloadSHA256,
            packSHA256: packSHA256,
            packStatus: entry(forPackSHA256: packSHA256)?.status,
            withdrawnPackSHA256: terminalWithdrawals
        )
    }
}

public enum PackStatusVerificationError: Error, Equatable, LocalizedError {
    case malformedEnvelope
    case unsupportedSchema
    case invalidThreshold
    case insufficientValidSignatures
    case invalidPayload(String)
    case notYetValid
    case expired
    case rollback
    case equivocation
    case withdrawnPackReactivated

    public var errorDescription: String? {
        switch self {
        case .malformedEnvelope: "The data-pack status response is malformed."
        case .unsupportedSchema: "The data-pack status response uses an unsupported schema."
        case .invalidThreshold: "The data-pack status trust policy is invalid."
        case .insufficientValidSignatures: "The data-pack status signature could not be verified."
        case let .invalidPayload(message): "The data-pack status response is invalid: \(message)"
        case .notYetValid: "The data-pack status response is dated too far in the future."
        case .expired: "The verified data-pack status has expired. Connect to the internet and try again."
        case .rollback: "An older data-pack status response was rejected."
        case .equivocation: "A conflicting data-pack status response was rejected."
        case .withdrawnPackReactivated: "A withdrawn data pack cannot be reactivated."
        }
    }
}

public struct PackStatusVerifier: Sendable {
    public static let schemaVersion = 1
    public static let signatureDomain = Data("AIC-PACK-STATUS-V1\0".utf8)
    public static let maximumPayloadBytes = 32 * 1_024
    public static let maximumEnvelopeBytes = 64 * 1_024
    public static let maximumEntries = 128
    public static let maximumLifetime: TimeInterval = 8 * 24 * 60 * 60
    public static let allowedFutureSkew: TimeInterval = 5 * 60

    private let trustAnchor: PackStatusTrustAnchor

    public init(trustAnchor: PackStatusTrustAnchor) {
        self.trustAnchor = trustAnchor
    }

    public func verify(
        envelopeData: Data,
        previous: PackStatusCheckpoint? = nil,
        now: Date = Date(),
        trustedTimeFloor: Date? = nil
    ) throws -> VerifiedPackStatus {
        guard envelopeData.count <= Self.maximumEnvelopeBytes,
              let envelope = try? JSONDecoder().decode(SignedPackStatusEnvelope.self, from: envelopeData),
              let payloadData = Data(base64Encoded: envelope.payload),
              payloadData.count <= Self.maximumPayloadBytes,
              let payload = try? JSONDecoder().decode(PackStatusPayload.self, from: payloadData) else {
            throw PackStatusVerificationError.malformedEnvelope
        }
        guard trustAnchor.threshold > 0,
              trustAnchor.threshold <= trustAnchor.publicKeys.count else {
            throw PackStatusVerificationError.invalidThreshold
        }

        var signingInput = Self.signatureDomain
        signingInput.append(payloadData)
        var validKeyIDs = Set<String>()
        for signed in envelope.signatures where !validKeyIDs.contains(signed.keyID) {
            guard let rawPublicKey = trustAnchor.publicKeys[signed.keyID],
                  let signature = Data(base64Encoded: signed.signature),
                  let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: rawPublicKey),
                  publicKey.isValidSignature(signature, for: signingInput) else { continue }
            validKeyIDs.insert(signed.keyID)
        }
        guard validKeyIDs.count >= trustAnchor.threshold else {
            throw PackStatusVerificationError.insufficientValidSignatures
        }

        try validate(payload: payload, now: now, trustedTimeFloor: trustedTimeFloor)
        let digest = Self.sha256Hex(payloadData)
        if let previous {
            guard payload.sequence >= previous.sequence else {
                throw PackStatusVerificationError.rollback
            }
            if payload.sequence == previous.sequence, digest != previous.payloadSHA256 {
                throw PackStatusVerificationError.equivocation
            }
            let reactivated = previous.withdrawnPackSHA256.contains { withdrawnSHA in
                payload.packs.first(where: { $0.sha256 == withdrawnSHA })?.status == .active
            }
            if reactivated {
                throw PackStatusVerificationError.withdrawnPackReactivated
            }
        }
        return VerifiedPackStatus(
            payload: payload,
            payloadSHA256: digest,
            envelopeData: envelopeData
        )
    }

    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func sha256Hex(fileAt url: URL) throws -> String {
        sha256Hex(try Data(contentsOf: url, options: [.mappedIfSafe]))
    }

    private func validate(
        payload: PackStatusPayload,
        now: Date,
        trustedTimeFloor: Date?
    ) throws {
        guard payload.schemaVersion == Self.schemaVersion else {
            throw PackStatusVerificationError.unsupportedSchema
        }
        guard payload.sequence > 0 else {
            throw PackStatusVerificationError.invalidPayload("sequence must be positive")
        }
        guard !payload.packs.isEmpty, payload.packs.count <= Self.maximumEntries else {
            throw PackStatusVerificationError.invalidPayload("pack catalog size is outside the supported range")
        }
        let hashes = payload.packs.map(\.sha256)
        guard Set(hashes).count == hashes.count,
              hashes.allSatisfy(Self.isLowercaseSHA256) else {
            throw PackStatusVerificationError.invalidPayload("pack hashes must be unique lowercase SHA-256 values")
        }
        for entry in payload.packs {
            switch entry.status {
            case .active:
                guard entry.reasonCode == nil else {
                    throw PackStatusVerificationError.invalidPayload("active entries cannot include a withdrawal reason")
                }
            case .withdrawn:
                guard let reason = entry.reasonCode,
                      !reason.isEmpty,
                      reason.count <= 64,
                      reason.unicodeScalars.allSatisfy({
                          CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
                              .contains($0)
                      }) else {
                    throw PackStatusVerificationError.invalidPayload("withdrawn entries require a bounded reason code")
                }
            }
        }

        let issuedAt = Date(timeIntervalSince1970: TimeInterval(payload.issuedAtUnix))
        let expiresAt = Date(timeIntervalSince1970: TimeInterval(payload.expiresAtUnix))
        guard expiresAt > issuedAt,
              expiresAt.timeIntervalSince(issuedAt) <= Self.maximumLifetime else {
            throw PackStatusVerificationError.invalidPayload("signed lifetime exceeds the supported window")
        }
        let effectiveNow = max(now, trustedTimeFloor ?? .distantPast)
        guard issuedAt <= effectiveNow.addingTimeInterval(Self.allowedFutureSkew) else {
            throw PackStatusVerificationError.notYetValid
        }
        guard effectiveNow < expiresAt else {
            throw PackStatusVerificationError.expired
        }
    }

    private static func isLowercaseSHA256(_ value: String) -> Bool {
        value.count == 64 && value.unicodeScalars.allSatisfy {
            ("0" ... "9").contains(Character($0)) || ("a" ... "f").contains(Character($0))
        }
    }
}
