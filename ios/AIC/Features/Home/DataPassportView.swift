import AICCore
import SwiftUI

struct DataPassportSelection: Identifiable {
    let summary: PackFreshnessSummary
    var id: String { summary.sourceThroughDate + summary.freshUntilDate }
}

struct DataHorizonView: View {
    let summary: PackFreshnessSummary
    let onOpenPassport: () -> Void

    private var presentation: DataFreshnessPresentation {
        DataFreshnessPresentation(summary: summary)
    }

    var body: some View {
        Button(action: onOpenPassport) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Label(presentation.statusTitle, systemImage: presentation.statusIcon)
                        .font(.caption2.weight(.black))
                        .tracking(0.7)
                        .foregroundStyle(presentation.accent)
                    Spacer()
                    Image(systemName: "info.circle")
                        .foregroundStyle(AICTheme.secondaryText)
                        .accessibilityHidden(true)
                }

                Text("DATA HORIZON · \(presentation.sourceThroughDisplay.uppercased())")
                    .font(.caption.weight(.black))
                    .tracking(0.8)
                    .foregroundStyle(Color.white)

                DataHorizonTimeline(summary: summary, accent: presentation.accent)

                Text(presentation.explanation)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AICTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text("View Data Passport")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AICTheme.lavender)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(presentation.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(presentation.accent.opacity(0.32), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens source dates, cutoff, coverage, and limitations.")
    }
}

struct DataHorizonErrorView: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("DATA UNAVAILABLE", systemImage: "exclamationmark.triangle.fill")
                .font(.caption2.weight(.black))
                .tracking(0.7)
                .foregroundStyle(AICTheme.coral)
            Text(message)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AICTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AICTheme.coral.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct DataHorizonTimeline: View {
    let summary: PackFreshnessSummary
    let accent: Color

    private var missingFraction: Double {
        let includedDays = 365.0
        let gapDays = Double(summary.daysSinceSourceThrough)
        return min(0.30, max(0.08, gapDays / (includedDays + gapDays)))
    }

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { proxy in
                let gapWidth = proxy.size.width * missingFraction
                HStack(spacing: 4) {
                    Capsule()
                        .fill(accent.opacity(0.68))
                    Capsule()
                        .fill(AICTheme.coral.opacity(0.20))
                        .overlay {
                            Capsule().stroke(AICTheme.coral.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        }
                        .frame(width: gapWidth)
                }
            }
            .frame(height: 7)

            HStack {
                Text(DataFreshnessPresentation.displayDate(summary.periodStart))
                Spacer()
                Text("THROUGH \(DataFreshnessPresentation.displayDate(summary.sourceThroughDate).uppercased())")
                Text("NOW")
                    .foregroundStyle(AICTheme.coral)
            }
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(AICTheme.secondaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Included history from \(DataFreshnessPresentation.displayDate(summary.periodStart)) through \(DataFreshnessPresentation.displayDate(summary.sourceThroughDate)). Source records dated after that horizon are not included."
        )
    }
}

struct DataPassportView: View {
    @Environment(\.dismiss) private var dismiss
    let summary: PackFreshnessSummary

    private var presentation: DataFreshnessPresentation {
        DataFreshnessPresentation(summary: summary)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AICBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        statusCard
                        provenanceCard
                        coverageCard
                        limitationsCard
                    }
                    .aicPagePadding()
                    .padding(.vertical, 14)
                }
            }
            .navigationTitle("Data Passport")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(AICTheme.mint)
    }

    private var statusCard: some View {
        AICCard {
            VStack(alignment: .leading, spacing: 10) {
                Label(presentation.statusTitle, systemImage: presentation.statusIcon)
                    .font(.caption.weight(.black))
                    .tracking(0.7)
                    .foregroundStyle(presentation.accent)
                Text("Historical data through \(presentation.sourceThroughDisplay)")
                    .font(.title2.weight(.black))
                Text(presentation.explanation)
                    .font(.subheadline)
                    .foregroundStyle(AICTheme.secondaryText)
                if summary.state != .blocked {
                    Text("Scans pause automatically on \(presentation.cutoffDisplay) if the pack is not replaced.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.white)
                }
            }
        }
    }

    private var provenanceCard: some View {
        AICCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Provenance")
                    .font(.headline.weight(.black))
                passportRow("Included window", value: "\(DataFreshnessPresentation.displayDate(summary.periodStart)) – \(presentation.sourceThroughDisplay)")
                passportRow("Source snapshot retrieved", value: DataFreshnessPresentation.displayTimestamp(summary.sourceRetrievedAt))
                passportRow("Scan-use cutoff", value: "\(presentation.cutoffDisplay) at 12:00 AM UTC")
                passportRow("Distribution lifecycle", value: DataFreshnessPresentation.displayDate(summary.expiresAtDate))
                Divider().overlay(Color.white.opacity(0.10))
                Link(destination: URL(string: "https://data.cityofchicago.org/d/ijzp-q8t2")!) {
                    Label("City of Chicago Data Portal source", systemImage: "arrow.up.right.square")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AICTheme.lavender)
                }
            }
        }
    }

    private var coverageCard: some View {
        AICCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("What is included")
                    .font(.headline.weight(.black))
                Text("Reported assault/battery, robbery, theft, and motor-vehicle theft records that pass the documented Chicago geography and category rules.")
                    .font(.subheadline)
                Label("Fixed 500 m / about 0.3 mi historical comparison", systemImage: "scope")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AICTheme.secondaryText)
                Label("Calculated locally from privacy-coarsened cells", systemImage: "iphone.and.arrow.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AICTheme.secondaryText)
            }
        }
    }

    private var limitationsCard: some View {
        AICCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Blind spots", systemImage: "eye.trianglebadge.exclamationmark")
                    .font(.headline.weight(.black))
                    .foregroundStyle(AICTheme.coral)
                Text("Reported incidents are not all incidents. The City source normally omits the most recent seven days. Records can arrive late, be revised, contain errors or omissions, or be affected by reporting and enforcement patterns. Approximate or missing geography and unsupported categories are excluded.")
                    .font(.subheadline)
                    .foregroundStyle(AICTheme.secondaryText)
                Text("Do not use AIC for immediate safety, emergencies, or route decisions.")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.white)
            }
        }
    }

    private func passportRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.caption2.weight(.black))
                .tracking(0.6)
                .foregroundStyle(AICTheme.secondaryText)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct DataFreshnessPresentation {
    let summary: PackFreshnessSummary

    var accent: Color {
        switch summary.state {
        case .withinUpdateWindow: AICTheme.lavender
        case .updateDueSoon: .orange
        case .blocked: AICTheme.coral
        }
    }

    var statusIcon: String {
        switch summary.state {
        case .withinUpdateWindow: "calendar.badge.clock"
        case .updateDueSoon: "clock.badge.exclamationmark"
        case .blocked: "pause.circle.fill"
        }
    }

    var statusTitle: String {
        switch summary.state {
        case .withinUpdateWindow:
            "WITHIN UPDATE WINDOW"
        case .updateDueSoon:
            "UPDATE DUE BY \(cutoffDisplay.uppercased())"
        case .blocked:
            "SCANS PAUSED"
        }
    }

    var explanation: String {
        switch summary.state {
        case .withinUpdateWindow:
            "Source records dated after \(sourceThroughDisplay) are not included. This is historical data, not a live scan."
        case .updateDueSoon:
            "Source records dated after \(sourceThroughDisplay) are not included. Replace this pack within \(summary.daysUntilCutoff) days."
        case .blocked:
            "This pack is outside AIC’s update window. Update the app before scanning again."
        }
    }

    var sourceThroughDisplay: String { Self.displayDate(summary.sourceThroughDate) }
    var cutoffDisplay: String { Self.displayDate(summary.freshUntilDate) }

    static func displayDate(_ isoDate: String) -> String {
        guard let date = isoDateFormatter.date(from: isoDate) else { return isoDate }
        return displayDateFormatter.string(from: date)
    }

    static func displayTimestamp(_ date: Date) -> String {
        timestampFormatter.string(from: date) + " UTC"
    }

    private static let isoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }()

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        return formatter
    }()
}
