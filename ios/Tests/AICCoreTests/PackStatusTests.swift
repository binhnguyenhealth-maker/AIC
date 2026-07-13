import CryptoKit
import XCTest
@testable import AICCore

final class PackStatusTests: XCTestCase {
    private let packSHA = String(repeating: "a", count: 64)
    private let otherPackSHA = String(repeating: "b", count: 64)
    private let now = Date(timeIntervalSince1970: 1_783_900_800) // 2026-07-13T00:00:00Z

    func testTwoOfThreeValidSignaturesAuthorizeExactPack() throws {
        let payload = makePayload(sequence: 7, status: .active)
        let envelope = try signedEnvelope(payload, signers: [0, 2])
        let verified = try verifier.verify(envelopeData: envelope, now: now)

        XCTAssertEqual(verified.payload, payload)
        XCTAssertEqual(verified.entry(forPackSHA256: packSHA)?.status, .active)
        XCTAssertNil(verified.entry(forPackSHA256: otherPackSHA))
    }

    func testOneSignatureCannotMeetThreshold() throws {
        let envelope = try signedEnvelope(makePayload(), signers: [1])
        XCTAssertThrowsError(try verifier.verify(envelopeData: envelope, now: now)) { error in
            XCTAssertEqual(error as? PackStatusVerificationError, .insufficientValidSignatures)
        }
    }

    func testDuplicateSignatureCannotMeetThreshold() throws {
        let payload = try payloadData(makePayload())
        let signature = try privateKeys[0].signature(for: signingInput(payload))
        let duplicate = PackStatusSignature(keyID: "release-a", signature: signature.base64EncodedString())
        let envelope = try JSONEncoder().encode(SignedPackStatusEnvelope(
            payload: payload.base64EncodedString(),
            signatures: [duplicate, duplicate]
        ))

        XCTAssertThrowsError(try verifier.verify(envelopeData: envelope, now: now)) { error in
            XCTAssertEqual(error as? PackStatusVerificationError, .insufficientValidSignatures)
        }
    }

    func testTamperedPayloadFailsSignatureVerification() throws {
        let original = makePayload(sequence: 7)
        let signed = try signedEnvelope(original, signers: [0, 1])
        var envelope = try JSONDecoder().decode(SignedPackStatusEnvelope.self, from: signed)
        let tampered = try payloadData(makePayload(sequence: 8))
        envelope = SignedPackStatusEnvelope(
            payload: tampered.base64EncodedString(),
            signatures: envelope.signatures
        )

        XCTAssertThrowsError(try verifier.verify(
            envelopeData: JSONEncoder().encode(envelope),
            now: now
        )) { error in
            XCTAssertEqual(error as? PackStatusVerificationError, .insufficientValidSignatures)
        }
    }

    func testLowerSequenceIsRejectedAsRollback() throws {
        let prior = try verifier.verify(
            envelopeData: signedEnvelope(makePayload(sequence: 8), signers: [0, 1]),
            now: now
        ).checkpoint(forPackSHA256: packSHA)
        let older = try signedEnvelope(makePayload(sequence: 7), signers: [0, 2])

        XCTAssertThrowsError(try verifier.verify(envelopeData: older, previous: prior, now: now)) { error in
            XCTAssertEqual(error as? PackStatusVerificationError, .rollback)
        }
    }

    func testSameSequenceDifferentPayloadIsRejectedAsEquivocation() throws {
        let prior = try verifier.verify(
            envelopeData: signedEnvelope(makePayload(sequence: 8), signers: [0, 1]),
            now: now
        ).checkpoint(forPackSHA256: packSHA)
        let conflicting = try signedEnvelope(
            makePayload(sequence: 8, status: .withdrawn, reasonCode: "source-error"),
            signers: [1, 2]
        )

        XCTAssertThrowsError(try verifier.verify(
            envelopeData: conflicting,
            previous: prior,
            now: now
        )) { error in
            XCTAssertEqual(error as? PackStatusVerificationError, .equivocation)
        }
    }

    func testWithdrawalIsTerminalForSamePackHash() throws {
        let withdrawn = try verifier.verify(
            envelopeData: signedEnvelope(
                makePayload(sequence: 8, status: .withdrawn, reasonCode: "quality-incident"),
                signers: [0, 1]
            ),
            now: now
        )
        let prior = withdrawn.checkpoint(forPackSHA256: packSHA)
        XCTAssertEqual(prior.packStatus, .withdrawn)
        XCTAssertEqual(prior.withdrawnPackSHA256, [packSHA])

        let attemptedReactivation = try signedEnvelope(
            makePayload(sequence: 9, status: .active),
            signers: [1, 2]
        )
        XCTAssertThrowsError(try verifier.verify(
            envelopeData: attemptedReactivation,
            previous: prior,
            now: now
        )) { error in
            XCTAssertEqual(error as? PackStatusVerificationError, .withdrawnPackReactivated)
        }
    }

    func testSignedExpiryAndTrustedTimeFloorFailClosed() throws {
        let envelope = try signedEnvelope(makePayload(), signers: [0, 1])
        let afterExpiry = now.addingTimeInterval(8 * 24 * 60 * 60)

        XCTAssertThrowsError(try verifier.verify(envelopeData: envelope, now: afterExpiry)) { error in
            XCTAssertEqual(error as? PackStatusVerificationError, .expired)
        }
        XCTAssertThrowsError(try verifier.verify(
            envelopeData: envelope,
            now: now.addingTimeInterval(-24 * 60 * 60),
            trustedTimeFloor: afterExpiry
        )) { error in
            XCTAssertEqual(error as? PackStatusVerificationError, .expired)
        }
    }

    func testCatalogRejectsDuplicateHashesAndUnboundedLifetime() throws {
        let duplicate = PackStatusPayload(
            schemaVersion: 1,
            sequence: 1,
            issuedAtUnix: Int64(now.timeIntervalSince1970),
            expiresAtUnix: Int64(now.addingTimeInterval(7 * 24 * 60 * 60).timeIntervalSince1970),
            packs: [
                PackStatusEntry(sha256: packSHA, status: .active),
                PackStatusEntry(sha256: packSHA, status: .active),
            ]
        )
        XCTAssertThrowsError(try verifier.verify(
            envelopeData: signedEnvelope(duplicate, signers: [0, 1]),
            now: now
        ))

        let tooLong = makePayload(expiresAfter: 9 * 24 * 60 * 60)
        XCTAssertThrowsError(try verifier.verify(
            envelopeData: signedEnvelope(tooLong, signers: [0, 1]),
            now: now
        ))
    }

    private var privateKeys: [Curve25519.Signing.PrivateKey] {
        get throws {
            try [1, 2, 3].map { byte in
                try Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: UInt8(byte), count: 32))
            }
        }
    }

    private var verifier: PackStatusVerifier {
        get throws {
            let keys = try privateKeys
            return PackStatusVerifier(trustAnchor: PackStatusTrustAnchor(
                threshold: 2,
                publicKeys: [
                    "release-a": keys[0].publicKey.rawRepresentation,
                    "release-b": keys[1].publicKey.rawRepresentation,
                    "release-c": keys[2].publicKey.rawRepresentation,
                ]
            ))
        }
    }

    private func makePayload(
        sequence: UInt64 = 7,
        status: PackRegistryStatus = .active,
        reasonCode: String? = nil,
        expiresAfter: TimeInterval = 7 * 24 * 60 * 60
    ) -> PackStatusPayload {
        PackStatusPayload(
            schemaVersion: 1,
            sequence: sequence,
            issuedAtUnix: Int64(now.timeIntervalSince1970),
            expiresAtUnix: Int64(now.addingTimeInterval(expiresAfter).timeIntervalSince1970),
            packs: [PackStatusEntry(sha256: packSHA, status: status, reasonCode: reasonCode)]
        )
    }

    private func payloadData(_ payload: PackStatusPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(payload)
    }

    private func signingInput(_ payload: Data) -> Data {
        var input = PackStatusVerifier.signatureDomain
        input.append(payload)
        return input
    }

    private func signedEnvelope(_ payload: PackStatusPayload, signers: [Int]) throws -> Data {
        let payload = try payloadData(payload)
        let keys = try privateKeys
        let keyIDs = ["release-a", "release-b", "release-c"]
        let signatures = try signers.map { index in
            PackStatusSignature(
                keyID: keyIDs[index],
                signature: try keys[index].signature(for: signingInput(payload)).base64EncodedString()
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(SignedPackStatusEnvelope(
            payload: payload.base64EncodedString(),
            signatures: signatures
        ))
    }
}
