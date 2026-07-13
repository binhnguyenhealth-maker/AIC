#if !GUEST_ONLY_V1
import AuthenticationServices
import SwiftUI

struct AuthScreen: View {
    @ObservedObject var model: AppModel
    @State private var rawNonce = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Spacer(minLength: 52)

                HStack(spacing: 10) {
                    Image(systemName: "scope")
                        .font(.title2.weight(.black))
                        .foregroundStyle(AICTheme.mint)
                    Text("AIC / CHICAGO")
                        .font(.caption.weight(.heavy))
                        .tracking(1.8)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("How cooked is\nthis block?")
                        .font(.system(size: 50, weight: .black, design: .rounded))
                        .tracking(-2.2)
                        .minimumScaleFactor(0.72)
                    Text("A quick, local estimate of historical reported-incident concentration for a fixed 500-meter (about 0.3-mile) radius—without uploading your scan location.")
                        .font(.title3)
                        .foregroundStyle(AICTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                AICCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Scored on this iPhone", systemImage: "iphone.and.arrow.forward")
                        Label("Official Chicago historical data", systemImage: "building.columns")
                        Label("Not live danger or personal risk", systemImage: "shield.lefthalf.filled")
                    }
                    .font(.subheadline.weight(.semibold))
                }

                VStack(spacing: 14) {
                    SignInWithAppleButton(.signIn) { request in
                        do {
                            let nonce = try AppleNonce.make()
                            rawNonce = nonce
                            request.requestedScopes = []
                            request.nonce = AppleNonce.sha256(nonce)
                        } catch {
                            model.present("A secure Apple sign-in request could not be created.")
                        }
                    } onCompletion: { result in
                        switch result {
                        case let .success(authorization):
                            guard !rawNonce.isEmpty else {
                                model.present("The sign-in request expired. Please try again.")
                                return
                            }
                            let nonce = rawNonce
                            rawNonce = ""
                            Task { await model.completeAppleAuthorization(authorization, rawNonce: nonce) }
                        case let .failure(error):
                            rawNonce = ""
                            model.handleAppleAuthorizationFailure(error)
                        }
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .disabled(model.isBusy)
                    .accessibilityHint("Creates or opens your AIC account using Apple.")

                    Button("Continue without an account") {
                        model.continueWithoutAccount()
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .disabled(model.isBusy)
                    .accessibilityHint("Returns to private on-device scanning without creating an account.")

                    Text("An account is optional and only adds a public @username to receipts. AIC requests no Apple name or email and never stores scan locations in your account.")
                        .font(.caption)
                        .foregroundStyle(AICTheme.secondaryText)
                        .multilineTextAlignment(.center)
                }

                if model.isBusy {
                    ProgressView("Securing your account…")
                        .frame(maxWidth: .infinity)
                        .tint(AICTheme.mint)
                }
            }
            .aicPagePadding()
            .padding(.bottom, 32)
        }
    }
}
#endif
