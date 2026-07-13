import AICCore
import SwiftUI

struct MainFlowView: View {
    private struct ScanRoute: Hashable {
        let id = UUID()
        let result: ChicagoScanResult

        static func == (lhs: ScanRoute, rhs: ScanRoute) -> Bool {
            lhs.id == rhs.id
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

    private enum Route: Hashable {
        case result(ScanRoute)
        case receipt(ScanRoute)
    }

    @ObservedObject var model: AppModel
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            HomeScreen(model: model) { scanResult in
                path.append(.result(ScanRoute(result: scanResult)))
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case let .result(scan):
                    ResultScreen(
                        result: scan.result,
                        distanceSystem: model.distanceSystem
                    ) { path.append(.receipt(scan)) }
                case let .receipt(scan):
                    ReceiptScreen(result: scan.result, username: model.username)
                }
            }
        }
        .tint(AICTheme.mint)
    }
}
