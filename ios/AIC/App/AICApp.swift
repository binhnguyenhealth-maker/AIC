import SwiftUI

@main
struct AICApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .preferredColorScheme(.dark)
                .task { await model.restoreSession() }
        }
    }
}

private struct RootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            AICBackground()
            switch model.phase {
            case .launching:
                ProgressView("Opening AIC…")
                    .tint(AICTheme.mint)
            case .signedOut:
                AuthScreen(model: model)
                    .transition(.opacity)
            case .needsUsername:
                UsernameScreen(model: model)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .guest, .ready:
                readyView
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.35), value: model.phase)
        .alert("AIC", isPresented: Binding(
            get: { model.presentedError != nil },
            set: { if !$0 { model.presentedError = nil } }
        )) {
            Button("OK", role: .cancel) { model.presentedError = nil }
        } message: {
            Text(model.presentedError ?? "Something went wrong.")
        }
    }

    @ViewBuilder
    private var readyView: some View {
#if DEBUG
        switch ShowcaseData.requestedScreen {
        case .result:
            NavigationStack {
                ResultScreen(
                    result: ShowcaseData.result,
                    distanceSystem: model.distanceSystem
                ) {}
            }
        case .receipt:
            NavigationStack { ReceiptScreen(result: ShowcaseData.result, username: model.username) }
        case .settings:
            SettingsScreen(model: model)
        case .passport:
            DataPassportView(summary: ShowcaseData.freshness)
        default:
            MainFlowView(model: model)
        }
#else
        MainFlowView(model: model)
#endif
    }
}
