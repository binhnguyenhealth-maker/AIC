#!/usr/bin/env swift

import CryptoKit
import Foundation

private let signatureDomain = Data("AIC-PACK-STATUS-V1\0".utf8)
private let keyIDs = ["release-a", "release-b", "release-c"]

private struct Signature: Codable {
    let keyID: String
    let signature: String
}

private struct Envelope: Codable {
    let payload: String
    let signatures: [Signature]
}

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

private func write(_ data: Data, to url: URL, permissions: Int? = nil) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try data.write(to: url, options: .atomic)
    if let permissions {
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
    }
}

private func generateKeys(in directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    var publicKeys: [String: String] = [:]
    for keyID in keyIDs {
        let keyURL = directory.appendingPathComponent("\(keyID).key")
        let privateKey: Curve25519.Signing.PrivateKey
        if FileManager.default.fileExists(atPath: keyURL.path) {
            let encoded = try String(contentsOf: keyURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let raw = Data(base64Encoded: encoded) else { fail("invalid private key \(keyURL.path)") }
            privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: raw)
        } else {
            privateKey = Curve25519.Signing.PrivateKey()
            try write(
                Data((privateKey.rawRepresentation.base64EncodedString() + "\n").utf8),
                to: keyURL,
                permissions: 0o600
            )
        }
        publicKeys[keyID] = privateKey.publicKey.rawRepresentation.base64EncodedString()
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    var encoded = try encoder.encode(publicKeys)
    encoded.append(0x0a)
    FileHandle.standardOutput.write(encoded)
}

private func sign(payloadURL: URL, keyDirectory: URL, outputURL: URL) throws {
    let payload = try Data(contentsOf: payloadURL)
    guard payload.count <= 32 * 1_024,
          let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
          object["schemaVersion"] as? Int == 1 else {
        fail("payload must be bounded schema-version 1 JSON")
    }
    var signingInput = signatureDomain
    signingInput.append(payload)
    let signatures = try keyIDs.map { keyID -> Signature in
        let keyURL = keyDirectory.appendingPathComponent("\(keyID).key")
        let encoded = try String(contentsOf: keyURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw = Data(base64Encoded: encoded) else { fail("invalid private key \(keyURL.path)") }
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: raw)
        return Signature(
            keyID: keyID,
            signature: try privateKey.signature(for: signingInput).base64EncodedString()
        )
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    var encoded = try encoder.encode(Envelope(
        payload: payload.base64EncodedString(),
        signatures: signatures
    ))
    encoded.append(0x0a)
    try write(encoded, to: outputURL)
}

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    fail("usage: PackStatusSigner.swift generate-keys KEY_DIRECTORY | sign PAYLOAD KEY_DIRECTORY OUTPUT")
}

do {
    switch arguments[1] {
    case "generate-keys" where arguments.count == 3:
        try generateKeys(in: URL(fileURLWithPath: arguments[2], isDirectory: true))
    case "sign" where arguments.count == 5:
        try sign(
            payloadURL: URL(fileURLWithPath: arguments[2]),
            keyDirectory: URL(fileURLWithPath: arguments[3], isDirectory: true),
            outputURL: URL(fileURLWithPath: arguments[4])
        )
    default:
        fail("usage: PackStatusSigner.swift generate-keys KEY_DIRECTORY | sign PAYLOAD KEY_DIRECTORY OUTPUT")
    }
} catch {
    fail(error.localizedDescription)
}
