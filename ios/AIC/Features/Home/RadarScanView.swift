import SwiftUI

struct RadarScanView: View {
    enum State: Equatable {
        case idle
        case locating
        case scanning
    }

    let state: State
    let distanceSystem: AICDistanceSystem

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1 / 30)) { timeline in
            let angle = sweepAngle(at: timeline.date)
            ZStack {
                radarGlow
                radarGrid
                sweep(angle: angle)
                blips
                centerMarker
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 260)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(accessibilityValue)
        }
    }

    private var radarGlow: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [AICTheme.mint.opacity(state == .scanning ? 0.2 : 0.1), .clear],
                    center: .center,
                    startRadius: 8,
                    endRadius: 132
                )
            )
            .overlay {
                Circle()
                    .stroke(AICTheme.mint.opacity(0.28), lineWidth: 1)
            }
    }

    private var radarGrid: some View {
        ZStack {
            ForEach([0.34, 0.64, 0.94], id: \.self) { scale in
                Circle()
                    .stroke(AICTheme.mint.opacity(scale == 0.94 ? 0.3 : 0.18), lineWidth: 1)
                    .scaleEffect(scale)
            }
            Rectangle()
                .fill(AICTheme.mint.opacity(0.12))
                .frame(width: 1)
                .padding(.vertical, 8)
            Rectangle()
                .fill(AICTheme.mint.opacity(0.12))
                .frame(height: 1)
                .padding(.horizontal, 8)
        }
    }

    private func sweep(angle: Angle) -> some View {
        RadarWedge()
            .fill(
                AngularGradient(
                    colors: [.clear, AICTheme.mint.opacity(state == .scanning ? 0.62 : 0.34)],
                    center: .center,
                    startAngle: .degrees(-42),
                    endAngle: .degrees(0)
                )
            )
            .padding(7)
            .rotationEffect(angle)
            .shadow(color: AICTheme.mint.opacity(state == .scanning ? 0.34 : 0.14), radius: 12)
    }

    private var blips: some View {
        GeometryReader { proxy in
            ZStack {
                radarBlip(at: CGPoint(x: proxy.size.width * 0.68, y: proxy.size.height * 0.31), delay: 0)
                radarBlip(at: CGPoint(x: proxy.size.width * 0.29, y: proxy.size.height * 0.58), delay: 0.35)
                radarBlip(at: CGPoint(x: proxy.size.width * 0.61, y: proxy.size.height * 0.76), delay: 0.7)
            }
        }
    }

    private func radarBlip(at point: CGPoint, delay: Double) -> some View {
        Circle()
            .fill(state == .scanning ? AICTheme.coral : AICTheme.mint)
            .frame(width: state == .scanning ? 8 : 6, height: state == .scanning ? 8 : 6)
            .shadow(color: state == .scanning ? AICTheme.coral : AICTheme.mint, radius: 7)
            .position(point)
            .opacity(state == .locating ? 0.34 : 0.9)
            .animation(.easeInOut(duration: 0.7).delay(delay), value: state)
    }

    private var centerMarker: some View {
        VStack(spacing: 3) {
            Image(systemName: state == .scanning ? "wave.3.right.circle.fill" : "location.fill")
                .font(.system(size: 24, weight: .black))
                .foregroundStyle(state == .scanning ? AICTheme.mint : AICTheme.coral)
                .contentTransition(.symbolEffect(.replace))
            Text(centerLabel)
                .font(.caption2.monospaced().weight(.black))
                .tracking(1.1)
                .foregroundStyle(.white)
        }
        .padding(12)
        .background(AICTheme.ink.opacity(0.86), in: Circle())
        .overlay { Circle().stroke(Color.white.opacity(0.12), lineWidth: 1) }
    }

    private func sweepAngle(at date: Date) -> Angle {
        guard !reduceMotion else { return .degrees(-35) }
        let speed = state == .scanning ? 150.0 : state == .locating ? 95.0 : 28.0
        return .degrees(date.timeIntervalSinceReferenceDate * speed)
    }

    private var centerLabel: String {
        switch state {
        case .idle: distanceSystem.compactRadius
        case .locating: "CENTER"
        case .scanning: "SCAN"
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .idle: "Historical incident radar ready"
        case .locating: "Centering the \(distanceSystem.accessibilityRadius) scan"
        case .scanning: "Comparing local historical incident data"
        }
    }

    private var accessibilityValue: String {
        "Chicago, fixed \(distanceSystem.accessibilityRadius) radius, processed on this iPhone"
    }
}

private struct RadarWedge: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        path.move(to: center)
        path.addArc(
            center: center,
            radius: min(rect.width, rect.height) / 2,
            startAngle: .degrees(-42),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

#Preview("Ready") {
    ZStack {
        AICBackground()
        RadarScanView(state: .idle, distanceSystem: .us)
            .padding(40)
    }
    .preferredColorScheme(.dark)
}

#Preview("Scanning") {
    ZStack {
        AICBackground()
        RadarScanView(state: .scanning, distanceSystem: .metric)
            .padding(40)
    }
    .preferredColorScheme(.dark)
}
