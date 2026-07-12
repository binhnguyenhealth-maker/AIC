import SwiftUI

enum AICTheme {
    static let ink = Color(red: 0.03, green: 0.04, blue: 0.055)
    static let panel = Color(red: 0.075, green: 0.085, blue: 0.11)
    static let elevated = Color(red: 0.11, green: 0.12, blue: 0.15)
    static let mint = Color(red: 0.82, green: 0.95, blue: 0.45)
    static let coral = Color(red: 1.0, green: 0.36, blue: 0.37)
    static let lavender = Color(red: 0.58, green: 0.51, blue: 1.0)
    static let secondaryText = Color.white.opacity(0.67)
}

struct AICBackground: View {
    var body: some View {
        ZStack {
            AICTheme.ink.ignoresSafeArea()
            LinearGradient(
                colors: [AICTheme.lavender.opacity(0.12), .clear, AICTheme.mint.opacity(0.04)],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            GeometryReader { proxy in
                Path { path in
                    let spacing: CGFloat = 36
                    stride(from: 0, through: proxy.size.width, by: spacing).forEach { x in
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: proxy.size.height))
                    }
                    stride(from: 0, through: proxy.size.height, by: spacing).forEach { y in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                    }
                }
                .stroke(Color.white.opacity(0.025), lineWidth: 0.5)
            }
            .ignoresSafeArea()
        }
    }
}

struct AICCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AICTheme.panel.opacity(0.96), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
    }
}

struct PrimaryActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(AICTheme.ink)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(AICTheme.mint.opacity(configuration.isPressed ? 0.72 : 1), in: RoundedRectangle(cornerRadius: 16))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

extension View {
    func aicPagePadding() -> some View { padding(.horizontal, 20) }
}
