import AICCore
import SwiftUI

struct OfflinePinPicker: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (ScanCoordinate) -> Void

    @State private var selection: ScanCoordinate?
    @State private var markerPoint: CGPoint?

    var body: some View {
        ZStack {
            AICBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("MANUAL / OFFLINE")
                                .font(.caption.weight(.heavy))
                                .tracking(1.7)
                                .foregroundStyle(AICTheme.mint)
                            Text("Tap a Chicago spot")
                                .font(.title.weight(.black))
                        }
                        Spacer()
                        Button("Close") { dismiss() }
                    }

                    Text("This simplified city picker uses no map service and uploads nothing. Tap approximately where you want to scan; the official boundary in the local pack validates it.")
                        .font(.subheadline)
                        .foregroundStyle(AICTheme.secondaryText)

                    GeometryReader { proxy in
                        ZStack {
                            RoundedRectangle(cornerRadius: 28)
                                .fill(AICTheme.panel)
                            ChicagoSilhouette()
                                .fill(AICTheme.lavender.opacity(0.28))
                                .overlay { ChicagoSilhouette().stroke(AICTheme.lavender, lineWidth: 2) }
                                .padding(24)
                            offlineGrid(size: proxy.size)
                                .clipShape(RoundedRectangle(cornerRadius: 28))
                            if let markerPoint {
                                ZStack {
                                    Circle().fill(AICTheme.coral).frame(width: 22, height: 22)
                                    Circle().stroke(.white, lineWidth: 2).frame(width: 30, height: 30)
                                }
                                .position(markerPoint)
                                .accessibilityHidden(true)
                            }
                        }
                        .contentShape(Rectangle())
                        .gesture(SpatialTapGesture().onEnded { value in
                            let x = min(max(0, value.location.x), proxy.size.width)
                            let y = min(max(0, value.location.y), proxy.size.height)
                            markerPoint = CGPoint(x: x, y: y)
                            selection = ScanCoordinate(
                                latitude: ChicagoBounds.north - Double(y / proxy.size.height) * (ChicagoBounds.north - ChicagoBounds.south),
                                longitude: ChicagoBounds.west + Double(x / proxy.size.width) * (ChicagoBounds.east - ChicagoBounds.west)
                            )
                        })
                        .accessibilityLabel("Offline Chicago location picker")
                        .accessibilityHint("Tap an approximate location, then choose Scan this spot.")
                    }
                    .frame(height: 340)

                    Text(selection == nil ? "Tap the map to place the private scan point." : "Point selected. The exact coordinate is not displayed, stored, or uploaded.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(selection == nil ? AICTheme.secondaryText : AICTheme.mint)
                }
                .aicPagePadding()
                .padding(.top, 20)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .bottom) {
            Button("Scan this spot") {
                if let selection { onSelect(selection) }
            }
            .buttonStyle(PrimaryActionStyle())
            .disabled(selection == nil)
            .opacity(selection == nil ? 0.48 : 1)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(AICTheme.ink.opacity(0.97))
        }
    }

    private func offlineGrid(size: CGSize) -> some View {
        Path { path in
            let spacing: CGFloat = 48
            stride(from: 0, through: size.width, by: spacing).forEach { x in
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            stride(from: 0, through: size.height, by: spacing).forEach { y in
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
        }
        .stroke(Color.white.opacity(0.07), lineWidth: 0.5)
    }
}

private struct ChicagoSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        let points: [CGPoint] = [
            CGPoint(x: 0.34, y: 0.03), CGPoint(x: 0.82, y: 0.04), CGPoint(x: 0.80, y: 0.18),
            CGPoint(x: 0.71, y: 0.25), CGPoint(x: 0.72, y: 0.43), CGPoint(x: 0.78, y: 0.57),
            CGPoint(x: 0.68, y: 0.71), CGPoint(x: 0.64, y: 0.96), CGPoint(x: 0.25, y: 0.94),
            CGPoint(x: 0.18, y: 0.77), CGPoint(x: 0.25, y: 0.59), CGPoint(x: 0.20, y: 0.42),
            CGPoint(x: 0.28, y: 0.27), CGPoint(x: 0.23, y: 0.13)
        ]
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: rect.minX + first.x * rect.width, y: rect.minY + first.y * rect.height))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height))
        }
        path.closeSubpath()
        return path
    }
}
