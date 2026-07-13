import AICCore
import Foundation

typealias PackSummary = PackFreshnessSummary

struct LocalScanEngine {
    private let packURL: URL?

    init(bundle: Bundle = .main, processInfo: ProcessInfo = .processInfo) {
        #if DEBUG
        if let override = processInfo.environment["AIC_CHICAGO_PACK_PATH"] {
            packURL = URL(fileURLWithPath: override)
        } else {
            packURL = bundle.url(forResource: "chicago_beta", withExtension: "sqlite")
        }
        #else
        packURL = bundle.url(forResource: "chicago_beta", withExtension: "sqlite")
        #endif
    }

    init(packURL: URL) {
        self.packURL = packURL
    }

    func packSummary() async throws -> PackSummary {
        guard let packURL else { throw ChicagoPackError.missingPack }
        return try await Task.detached(priority: .utility) {
            try ChicagoPack.inspectFreshness(at: packURL)
        }.value
    }

    func scan(at coordinate: ScanCoordinate) async throws -> ChicagoScanResult {
        guard let packURL else { throw ChicagoPackError.missingPack }
        return try await Task.detached(priority: .userInitiated) {
            let pack = try ChicagoPack(url: packURL)
            return try pack.scan(at: coordinate)
        }.value
    }
}
