import AICCore
import SwiftUI

struct ReceiptScreen: View {
    let result: ChicagoScanResult
    let username: String

    @State private var showUsername: Bool
    @State private var showNeighborhood = true
    @State private var artifact: ReceiptArtifact?
    @State private var rendering = false
    @State private var errorMessage: String?

    init(result: ChicagoScanResult, username: String) {
        self.result = result
        self.username = UsernamePolicy.normalize(username)
        _showUsername = State(initialValue: !self.username.isEmpty)
    }

    private var hasUsername: Bool { !username.isEmpty }

    private var payload: CookedReceiptPayload {
        ReceiptComposer.make(
            result: result,
            username: username,
            showUsername: showUsername,
            locationMode: showNeighborhood ? .neighborhood : .cityOnly
        )
    }

    var body: some View {
        ZStack {
            AICBackground()
            ScrollView {
                VStack(spacing: 18) {
                    ReceiptCardView(payload: payload)
                        .aspectRatio(4 / 5, contentMode: .fit)
                        .accessibilityElement(children: .combine)

                    AICCard {
                        VStack(spacing: 4) {
                            if hasUsername {
                                Toggle("Show @\(username)", isOn: $showUsername)
                                Divider().overlay(Color.white.opacity(0.08))
                            }
                            Toggle("Show \(result.neighborhood)", isOn: $showNeighborhood)
                        }
                        .font(.subheadline.weight(.semibold))
                        .tint(AICTheme.mint)
                    }

                    Text(hasUsername
                         ? "This receipt links your public username to the approximate area shown when both visibility options are on. Exact coordinates, addresses, routes, and timestamps cannot be included."
                         : "This receipt can show an approximate area, but it never includes a username, exact coordinates, address, route, or timestamp.")
                        .font(.caption)
                        .foregroundStyle(AICTheme.secondaryText)
                        .multilineTextAlignment(.leading)

                    Button {
                        renderForSharing()
                    } label: {
                        if rendering {
                            HStack { ProgressView().tint(AICTheme.ink); Text("Rendering locally…") }
                        } else {
                            Label("Share image", systemImage: "square.and.arrow.up")
                        }
                    }
                    .buttonStyle(PrimaryActionStyle())
                    .disabled(rendering)
                }
                .aicPagePadding()
                .padding(.top, 8)
                .padding(.bottom, 36)
            }
        }
        .navigationTitle("Cooked Receipt")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $artifact) { artifact in
            ShareSheet(artifact: artifact) { self.artifact = nil }
        }
        .alert("Receipt blocked", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "The receipt could not be prepared.")
        }
    }

    private func renderForSharing() {
        rendering = true
        do {
            artifact = try ReceiptArtifactRenderer.render(payload)
        } catch {
            errorMessage = error.localizedDescription
        }
        rendering = false
    }
}
