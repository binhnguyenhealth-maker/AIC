import SwiftUI

@main
struct AICApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .preferredColorScheme(.dark)
#if GUEST_ONLY_V1
                .task { model.prepare() }
#else
                .task { await model.restoreSession() }
#endif
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
#if !GUEST_ONLY_V1
            case .signedOut:
                AuthScreen(model: model)
                    .transition(.opacity)
            case .needsUsername:
                UsernameScreen(model: model)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .ready:
                readyView
#endif
            case .guest:
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
            NavigationStack { ReceiptScreen(result: ShowcaseData.result) }
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
