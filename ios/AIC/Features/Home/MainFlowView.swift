import AICCore
import SwiftUI

struct MainFlowView: View {
    private enum Route: Hashable {
        case result
        case receipt
    }

    @ObservedObject var model: AppModel
    @State private var path: [Route] = []
    @State private var result: ChicagoScanResult?

    var body: some View {
        NavigationStack(path: $path) {
            HomeScreen(model: model) { scanResult in
                result = scanResult
                path.append(.result)
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .result:
                    if let result {
                        ResultScreen(result: result) { path.append(.receipt) }
                    }
                case .receipt:
                    if let result {
                        ReceiptScreen(result: result, username: model.username)
                    }
                }
            }
        }
        .tint(AICTheme.mint)
    }
}
