#if !GUEST_ONLY_V1
import AuthenticationServices
#endif
import SwiftUI

struct SettingsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: AppModel

#if !GUEST_ONLY_V1
    @State private var showDeletionFlow = false
#endif

    var body: some View {
        NavigationStack {
            ZStack {
                AICBackground()
                List {
#if !GUEST_ONLY_V1
                    if model.isSignedIn {
                        Section("Public account") {
                            LabeledContent("Username", value: "@\(model.username)")
                            Text("Your username is public when included on a Cooked Receipt. Ordinary scan points are not stored in this account.")
                                .font(.caption)
                                .foregroundStyle(AICTheme.secondaryText)
                        }
                    } else {
                        Section("Private on-device mode") {
                            Label("No account", systemImage: "iphone.and.arrow.forward")
                            Text("Scanning and reports work without an account. Sign in only if you want a public @username on receipts.")
                                .font(.caption)
                                .foregroundStyle(AICTheme.secondaryText)
                            Button("Sign in with Apple") {
                                model.startSignIn()
                                dismiss()
                            }
                        }
                    }
#else
                    Section("On-device mode") {
                        Label("Private by default", systemImage: "iphone.and.arrow.forward")
                        Text("Scans and Cooked Receipts are created on this iPhone. Scan locations are never uploaded or saved.")
                            .font(.caption)
                            .foregroundStyle(AICTheme.secondaryText)
                    }
#endif

                    Section("Display") {
                        Picker("Distance units", selection: $model.measurementPreference) {
                            ForEach(AICMeasurementPreference.allCases) { preference in
                                Text(preference.displayName).tag(preference)
                            }
                        }
                        Text("AIC always calculates the same exact 500-metre radius. This setting only changes how that distance is displayed. Automatic follows your iPhone measurement system.")
                            .font(.caption)
                            .foregroundStyle(AICTheme.secondaryText)
                    }

                    Section("Privacy & help") {
                        if let privacyURL = configuredURL(for: "AIC_PRIVACY_URL") {
                            Link(destination: privacyURL) {
                                Label("Privacy policy", systemImage: "hand.raised")
                            }
                        }
                        if let supportURL = configuredURL(for: "AIC_SUPPORT_URL") {
                            Link(destination: supportURL) {
                                Label("Support", systemImage: "questionmark.circle")
                            }
                        }
                        if let termsURL = configuredURL(for: "AIC_TERMS_URL") {
                            Link(destination: termsURL) {
                                Label("Terms of use", systemImage: "doc.text")
                            }
                        }
                        if let methodologyURL = configuredURL(for: "AIC_METHODOLOGY_URL") {
                            Link(destination: methodologyURL) {
                                Label("Methodology", systemImage: "function")
                            }
                        }
                        Label("Foreground location only", systemImage: "location.circle")
                        Text("AIC never requests background location and does not save scan history.")
                            .font(.caption)
                            .foregroundStyle(AICTheme.secondaryText)
                    }

#if !GUEST_ONLY_V1
                    if model.isSignedIn {
                        Section {
                            Button("Log out", role: .destructive) {
                                Task { await model.logout(); dismiss() }
                            }
                            .disabled(model.isBusy)
                        } footer: {
                            Text("Logout revokes the active AIC session and removes credentials from this iPhone.")
                        }

                        Section {
                            Button("Delete account", role: .destructive) {
                                showDeletionFlow = true
                            }
                            .disabled(model.isBusy)
                        } footer: {
                            Text("Deletion disables the account, revokes Apple and AIC credentials, removes the username and user-controlled account data, and clears local credentials and temporary receipts. The public Chicago data pack contains no account data and may remain.")
                        }
                    }
#endif
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .toolbar { Button("Done") { dismiss() } }
#if !GUEST_ONLY_V1
            .sheet(isPresented: $showDeletionFlow) {
                DeleteAccountSheet(model: model) {
                    showDeletionFlow = false
                    dismiss()
                }
            }
            .overlay {
                if model.isBusy {
                    ZStack {
                        Color.black.opacity(0.42).ignoresSafeArea()
                        ProgressView("Securing account change…")
                            .padding(20)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
#endif
        }
    }

    private func configuredURL(for key: String) -> URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              let url = URL(string: value), url.scheme == "https" else { return nil }
        return url
    }
}

#if !GUEST_ONLY_V1
private struct DeleteAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: AppModel
    let onDeleted: () -> Void

    @State private var confirmation = ""
    @State private var rawNonce = ""

    var body: some View {
        NavigationStack {
            ZStack {
                AICBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Image(systemName: "person.crop.circle.badge.minus")
                            .font(.system(size: 46))
                            .foregroundStyle(AICTheme.coral)
                        Text("Delete your account")
                            .font(.largeTitle.weight(.black))
                        Text("This disables your account, revokes Apple and AIC credentials, removes your public username and user-controlled account data, and clears credentials and temporary receipts from this iPhone.")
                            .foregroundStyle(AICTheme.secondaryText)
                        TextField("Type DELETE", text: $confirmation)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .padding(16)
                            .background(AICTheme.elevated, in: RoundedRectangle(cornerRadius: 14))
                        Text("Fresh Sign in with Apple confirmation is required. The proof expires in five minutes and is used once.")
                            .font(.caption)
                            .foregroundStyle(AICTheme.secondaryText)

                        SignInWithAppleButton(.continue) { request in
                            do {
                                let nonce = try AppleNonce.make()
                                rawNonce = nonce
                                request.requestedScopes = []
                                request.nonce = AppleNonce.sha256(nonce)
                            } catch {
                                model.present("A secure Apple confirmation could not be created.")
                            }
                        } onCompletion: { result in
                            switch result {
                            case let .success(authorization):
                                guard confirmation == "DELETE", !rawNonce.isEmpty else { return }
                                let nonce = rawNonce
                                rawNonce = ""
                                Task {
                                    if await model.deleteAccount(after: authorization, rawNonce: nonce) {
                                        onDeleted()
                                    }
                                }
                            case let .failure(error):
                                rawNonce = ""
                                model.handleAppleAuthorizationFailure(error)
                            }
                        }
                        .signInWithAppleButtonStyle(.white)
                        .frame(height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .disabled(confirmation != "DELETE" || model.isBusy)
                    }
                    .aicPagePadding()
                    .padding(.vertical, 28)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Permanent deletion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Cancel") { dismiss() } }
            .interactiveDismissDisabled(model.isBusy)
        }
    }
}
#endif
