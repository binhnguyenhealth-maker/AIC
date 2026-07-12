import AICCore
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct ReceiptArtifact: Identifiable {
    let id = UUID()
    let fileURL: URL
}

enum ReceiptArtifactError: LocalizedError {
    case renderingFailed
    case metadataDetected

    var errorDescription: String? {
        switch self {
        case .renderingFailed: "The receipt image could not be rendered."
        case .metadataDetected: "The receipt was blocked because image metadata was detected."
        }
    }
}

@MainActor
enum ReceiptArtifactRenderer {
    static func render(_ payload: CookedReceiptPayload) throws -> ReceiptArtifact {
        let content = ReceiptCardView(payload: payload)
            .frame(width: 360, height: 450)
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: 360, height: 450)
        renderer.scale = 3
        guard let image = renderer.uiImage,
              let cgImage = image.cgImage,
              let data = ReceiptImagePrivacyAudit.encodeMetadataFreePNG(cgImage) else {
            throw ReceiptArtifactError.renderingFailed
        }
        guard ReceiptImagePrivacyAudit.isMetadataFreePNG(data) else {
            throw ReceiptArtifactError.metadataDetected
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("aic-receipt-\(UUID().uuidString)")
            .appendingPathExtension("png")
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return ReceiptArtifact(fileURL: url)
    }
}

enum ReceiptImagePrivacyAudit {
    private static let pngSignature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]

    // Retain only PNG's critical image-data chunks. Every ancillary chunk is removed because it
    // can carry metadata and is unnecessary for displaying this rendered RGBA receipt.
    private static let allowedChunkTypes: Set<String> = [
        "IHDR", "PLTE", "IDAT", "IEND"
    ]

    private struct PNGChunk {
        let type: String
        let range: Range<Int>
    }

    static func encodeMetadataFreePNG(_ image: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }
        // Supplying no source properties prevents metadata from being copied into the destination.
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        // ImageIO still synthesizes a physical eXIf chunk containing pixel dimensions. Strip every
        // ancillary chunk from the encoded bytes, retaining the original CRC-protected image chunks.
        return strippingAncillaryChunks(from: output as Data)
    }

    static func isMetadataFreePNG(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let imageType = CGImageSourceGetType(source),
              imageType as String == UTType.png.identifier,
              CGImageSourceGetCount(source) == 1,
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil,
              let chunkTypes = chunkTypes(in: data),
              chunkTypes.first == "IHDR",
              chunkTypes.last == "IEND",
              chunkTypes.filter({ $0 == "IHDR" }).count == 1,
              chunkTypes.filter({ $0 == "IEND" }).count == 1,
              chunkTypes.contains("IDAT") else {
            return false
        }
        return chunkTypes.allSatisfy(allowedChunkTypes.contains)
    }

    static func chunkTypes(in data: Data) -> [String]? {
        let bytes = [UInt8](data)
        return parsedChunks(in: bytes)?.map(\.type)
    }

    private static func strippingAncillaryChunks(from data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard let chunks = parsedChunks(in: bytes) else { return nil }
        var sanitized = Data(pngSignature)
        for chunk in chunks where allowedChunkTypes.contains(chunk.type) {
            sanitized.append(contentsOf: bytes[chunk.range])
        }
        return sanitized
    }

    private static func parsedChunks(in bytes: [UInt8]) -> [PNGChunk]? {
        guard bytes.count >= 20, Array(bytes.prefix(8)) == pngSignature else { return nil }

        var offset = 8
        var result: [PNGChunk] = []
        while offset <= bytes.count - 12 {
            let length = (Int(bytes[offset]) << 24)
                | (Int(bytes[offset + 1]) << 16)
                | (Int(bytes[offset + 2]) << 8)
                | Int(bytes[offset + 3])
            guard length <= bytes.count - offset - 12 else { return nil }

            let typeBytes = bytes[(offset + 4)..<(offset + 8)]
            guard typeBytes.allSatisfy({
                (65...90).contains($0) || (97...122).contains($0)
            }), let type = String(bytes: typeBytes, encoding: .ascii) else { return nil }

            let nextOffset = offset + 12 + length
            result.append(PNGChunk(type: type, range: offset..<nextOffset))
            if type == "IEND" {
                return length == 0 && nextOffset == bytes.count ? result : nil
            }
            offset = nextOffset
        }
        return nil
    }
}

enum ReceiptArtifactStore {
    static func removeAllTemporaryReceipts() {
        let directory = FileManager.default.temporaryDirectory
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        for url in urls where url.lastPathComponent.hasPrefix("aic-receipt-") {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
