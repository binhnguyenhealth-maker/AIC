import AICCore
import ImageIO
import XCTest
@testable import AIC

final class ReceiptRenderingPrivacyTests: XCTestCase {
    @MainActor
    func testExportIs1080By1350PNGWithNoEXIFOrGPS() throws {
        let artifact = try ReceiptArtifactRenderer.render(fixturePayload())
        defer { try? FileManager.default.removeItem(at: artifact.fileURL) }
        let data = try Data(contentsOf: artifact.fileURL)
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "aic-receipt-metadata-proof.png"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertTrue(ReceiptImagePrivacyAudit.isMetadataFreePNG(data))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        XCTAssertEqual(CGImageSourceGetPixelWidth(source), 1080)
        XCTAssertEqual(CGImageSourceGetPixelHeight(source), 1350)
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
        XCTAssertNil(properties[kCGImagePropertyTIFFDictionary])
        // ImageIO may synthesize semantic properties that are not embedded PNG chunks. The raw
        // chunk allowlist is the authoritative check for embedded receipt metadata.
        let chunkTypes = try XCTUnwrap(ReceiptImagePrivacyAudit.chunkTypes(in: data))
        XCTAssertTrue(Set(["eXIf", "tEXt", "zTXt", "iTXt", "tIME"]).isDisjoint(with: chunkTypes))
    }

    @MainActor
    func testHiddenOptionsAreReflectedInRenderedPayload() throws {
        let result = fixtureResult()
        let payload = ReceiptComposer.make(
            result: result,
            locationMode: .hidden
        )
        XCTAssertNil(payload.locationLabel)
        let artifact = try ReceiptArtifactRenderer.render(payload)
        defer { try? FileManager.default.removeItem(at: artifact.fileURL) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifact.fileURL.path))
    }

    private func fixturePayload() -> CookedReceiptPayload {
        ReceiptComposer.make(
            result: fixtureResult(),
            locationMode: .neighborhood
        )
    }

    private func fixtureResult() -> ChicagoScanResult {
        ChicagoScanResult(
            cookedScore: 75,
            chicagoPercentile: 73.4,
            estimatedIncidentCount: 42,
            categoryCounts: [
                CategoryCount(category: .assaultBattery, count: 12),
                CategoryCount(category: .robbery, count: 6),
                CategoryCount(category: .theft, count: 20),
                CategoryCount(category: .motorVehicleTheft, count: 4)
            ],
            neighborhood: "Near West Side",
            sourceThroughDate: "2026-06-30",
            periodStart: "2025-07-01",
            methodologyVersion: "beta-cell250-q5-area-v3"
        )
    }
}

private func CGImageSourceGetPixelWidth(_ source: CGImageSource) -> Int {
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    return properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
}

private func CGImageSourceGetPixelHeight(_ source: CGImageSource) -> Int {
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    return properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
}
