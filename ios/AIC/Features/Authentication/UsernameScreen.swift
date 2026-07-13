#if !GUEST_ONLY_V1
import AICCore
import SwiftUI

struct UsernameScreen: View {
    @ObservedObject var model: AppModel
    @FocusState private var isFocused: Bool

    private var validation: UsernameValidation {
        UsernamePolicy.validate(model.usernameDraft)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Spacer(minLength: 52)

                Text("PICK YOUR HANDLE")
                    .font(.caption.weight(.heavy))
                    .tracking(1.8)
                    .foregroundStyle(AICTheme.mint)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Your receipt\nsignature.")
                        .font(.system(size: 46, weight: .black, design: .rounded))
                        .tracking(-2)
                    Text("We suggested a unique username. Edit it now or keep the one below.")
                        .font(.title3)
                        .foregroundStyle(AICTheme.secondaryText)
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 4) {
                        Text("@")
                            .foregroundStyle(AICTheme.mint)
                            .font(.title2.weight(.bold))
                        TextField("username", text: $model.usernameDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.asciiCapable)
                            .font(.title2.weight(.bold).monospaced())
                            .focused($isFocused)
                            .onChange(of: model.usernameDraft) { _, value in
                                let normalized = UsernamePolicy.normalize(value)
                                if normalized != value { model.usernameDraft = normalized }
                            }
                    }
                    .padding(.horizontal, 18)
                    .frame(minHeight: 62)
                    .background(AICTheme.elevated, in: RoundedRectangle(cornerRadius: 17))
                    .overlay {
                        RoundedRectangle(cornerRadius: 17)
                            .stroke(validationColor, lineWidth: 1.5)
                    }

                    validationMessage
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(validationColor)

                    Button("Try another suggestion") {
                        Task { await model.requestUsernameSuggestion() }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AICTheme.lavender)
                    .disabled(model.isBusy)
                }

                AICCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Public by design", systemImage: "person.crop.circle.badge.checkmark")
                            .font(.headline)
                        Text("When username visibility is on, a Cooked Receipt links this public username to the approximate Chicago area shown. Ordinary scans stay local.")
                            .font(.subheadline)
                            .foregroundStyle(AICTheme.secondaryText)
                    }
                }

                Button {
                    Task { await model.claimUsername() }
                } label: {
                    if model.isBusy {
                        ProgressView().tint(AICTheme.ink)
                    } else {
                        Text("Claim @\(UsernamePolicy.normalize(model.usernameDraft))")
                    }
                }
                .buttonStyle(PrimaryActionStyle())
                .disabled(!isValid || model.isBusy)
            }
            .aicPagePadding()
            .padding(.bottom, 32)
        }
        .onAppear { isFocused = model.usernameDraft.isEmpty }
    }

    private var isValid: Bool {
        if case .valid = validation { return true }
        return false
    }

    private var validationColor: Color {
        isValid ? AICTheme.mint : AICTheme.coral
    }

    @ViewBuilder
    private var validationMessage: some View {
        switch validation {
        case .valid:
            Text("Looks good. The server confirms uniqueness when you claim it.")
        case let .invalid(message):
            Text(message)
        }
    }
}
#endif
