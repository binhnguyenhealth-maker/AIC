import AICCore
import SwiftUI

struct ReceiptCardView: View {
    let payload: CookedReceiptPayload

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / 360
            ZStack {
                LinearGradient(
                    colors: [AICTheme.panel, AICTheme.ink, Color(red: 0.12, green: 0.08, blue: 0.14)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                cityGrid
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("AIC")
                            .font(.system(size: 20 * scale, weight: .black, design: .rounded))
                        Spacer()
                        Text("CHICAGO / BETA")
                            .font(.system(size: 8 * scale, weight: .black))
                            .tracking(1.2 * scale)
                            .foregroundStyle(AICTheme.mint)
                    }

                    Spacer()

                    Text("COOKED SCORE")
                        .font(.system(size: 10 * scale, weight: .black))
                        .tracking(1.4 * scale)
                        .foregroundStyle(AICTheme.coral)
                    Text("\(payload.cookedScore)")
                        .font(.system(size: 94 * scale, weight: .black, design: .rounded))
                        .tracking(-6 * scale)
                        .lineLimit(1)
                    Text("\(ordinal(payload.chicagoPercentile)) percentile within Chicago")
                        .font(.system(size: 17 * scale, weight: .bold, design: .rounded))

                    Spacer()

                    HStack(spacing: 10 * scale) {
                        receiptPill("Est. main: \(payload.mainCategory)", icon: "chart.bar.fill", scale: scale)
                        receiptPill("≈\(payload.estimatedIncidentCount) estimated incidents", icon: "doc.text.fill", scale: scale)
                    }

                    if payload.username != nil || payload.locationLabel != nil {
                        HStack(spacing: 7 * scale) {
                            if let username = payload.username {
                                Text("@\(username)")
                            }
                            if payload.username != nil, payload.locationLabel != nil {
                                Text("•").foregroundStyle(AICTheme.secondaryText)
                            }
                            if let location = payload.locationLabel {
                                Text(location)
                            }
                        }
                        .font(.system(size: 12 * scale, weight: .bold))
                        .padding(.top, 15 * scale)
                    }

                    Text("\(payload.broadTimeBucket) · Historical source through \(payload.sourceThroughDate)")
                        .font(.system(size: 9 * scale, weight: .semibold))
                        .foregroundStyle(AICTheme.secondaryText)
                        .padding(.top, 6 * scale)

                    Text("Privacy-coarsened historical estimate—not live safety or personal risk.")
                        .font(.system(size: 8 * scale, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.53))
                        .padding(.top, 12 * scale)
                }
                .padding(24 * scale)
                .foregroundStyle(Color.white)
            }
            .clipShape(RoundedRectangle(cornerRadius: 30 * scale, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 30 * scale, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            }
        }
        .background(AICTheme.ink)
    }

    private var cityGrid: some View {
        GeometryReader { proxy in
            Path { path in
                stride(from: 0, through: proxy.size.width, by: 28).forEach { x in
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: proxy.size.height))
                }
                stride(from: 0, through: proxy.size.height, by: 28).forEach { y in
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                }
            }
            .stroke(AICTheme.lavender.opacity(0.09), lineWidth: 0.5)
        }
    }

    private func receiptPill(_ text: String, icon: String, scale: CGFloat) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 9 * scale, weight: .bold))
            .lineLimit(1)
            .padding(.horizontal, 9 * scale)
            .padding(.vertical, 7 * scale)
            .background(Color.white.opacity(0.09), in: Capsule())
    }

    private func ordinal(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)th"
    }
}
