import AICCore
import Foundation

typealias PackSummary = PackFreshnessSummary

struct LocalScanEngine {
    private let packURL: URL?
    private let statusAuthorizer: any PackStatusAuthorizing

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
        statusAuthorizer = PackStatusClient.shared
    }

    init(packURL: URL, statusAuthorizer: any PackStatusAuthorizing) {
        self.packURL = packURL
        self.statusAuthorizer = statusAuthorizer
    }

    func packSummary() async throws -> PackSummary {
        guard let packURL else { throw ChicagoPackError.missingPack }
        try await statusAuthorizer.authorize(packAt: packURL, refresh: true)
        return try await Task.detached(priority: .utility) {
            try ChicagoPack.inspectFreshness(at: packURL)
        }.value
    }

    func scan(at coordinate: ScanCoordinate) async throws -> ChicagoScanResult {
        guard let packURL else { throw ChicagoPackError.missingPack }
        // Status refreshes happen on foreground load, not synchronously with a
        // scan, so the public endpoint cannot observe scan timing.
        try await statusAuthorizer.authorize(packAt: packURL, refresh: false)
        return try await Task.detached(priority: .userInitiated) {
            let pack = try ChicagoPack(url: packURL)
            return try pack.scan(at: coordinate)
        }.value
    }
}
