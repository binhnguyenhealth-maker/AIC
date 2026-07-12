import AICCore
import SwiftUI

struct ResultScreen: View {
    let result: ChicagoScanResult
    let onShare: () -> Void

    @State private var showMethodology = false

    var body: some View {
        ZStack {
            AICBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    scoreHero
                    categoryBreakdown
                    sourceCard
                }
                .aicPagePadding()
                .padding(.top, 8)
                .padding(.bottom, 36)
            }
        }
        .navigationTitle("Cooked Score Beta")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showMethodology) {
            MethodologySheet(result: result)
                .presentationDetents([.medium, .large])
        }
    }

    private var scoreHero: some View {
        AICCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("COOKED SCORE")
                            .font(.caption.weight(.black))
                            .tracking(1.5)
                            .foregroundStyle(AICTheme.coral)
                        Text("\(result.cookedScore)")
                            .font(.system(size: 88, weight: .black, design: .rounded))
                            .tracking(-5)
                            .accessibilityLabel("Cooked Score \(result.cookedScore) out of 100")
                    }
                    Spacer()
                    Text("BETA")
                        .font(.caption2.weight(.black))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AICTheme.coral, in: Capsule())
                }

                Text("\(ordinal(Int(result.chicagoPercentile.rounded()))) percentile within Chicago")
                    .font(.title3.weight(.bold))
                Text("Estimated main category: \(result.mainCategory.category.displayName)")
                    .font(.headline)
                    .foregroundStyle(AICTheme.mint)

                Text(ChicagoScanResult.requiredDisclaimer)
                    .font(.caption)
                    .foregroundStyle(AICTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(ChicagoScanResult.estimateDisclosure)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AICTheme.secondaryText)

                Button(action: onShare) {
                    Label("Make a Cooked Receipt", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(PrimaryActionStyle())
            }
        }
    }

    private var categoryBreakdown: some View {
        AICCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Estimated category breakdown")
                        .font(.headline.weight(.black))
                    Spacer()
                    Text("Estimated total ≈\(result.estimatedIncidentCount)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AICTheme.secondaryText)
                }
                ForEach(result.categoryCounts) { item in
                    VStack(spacing: 7) {
                        HStack {
                            Text(item.category.displayName)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("≈\(item.count)")
                                .font(.subheadline.monospacedDigit().weight(.bold))
                        }
                        GeometryReader { proxy in
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(color(for: item.category))
                                        .frame(width: proxy.size.width * categoryFraction(item.count))
                                }
                        }
                        .frame(height: 7)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var sourceCard: some View {
        AICCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(result.neighborhood, systemImage: "mappin.circle.fill")
                    .font(.headline)
                Text("Official Chicago community-area boundary · fixed 500 m estimate")
                    .font(.caption)
                    .foregroundStyle(AICTheme.secondaryText)
                Label("Local beta result · privacy-coarsened, non-overlapping source cells", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AICTheme.mint)
                Divider().overlay(Color.white.opacity(0.12))
                HStack {
                    VStack(alignment: .leading) {
                        Text("SOURCE THROUGH").font(.caption2.weight(.black))
                        Text(result.sourceThroughDate).font(.subheadline.weight(.bold))
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("WINDOW START").font(.caption2.weight(.black))
                        Text(result.periodStart).font(.subheadline.weight(.bold))
                    }
                }
                Text("Source: City of Chicago Data Portal, Crimes - 2001 to Present")
                    .font(.caption.weight(.semibold))
                Text("Historical reported incidents can be delayed, revised, underreported, or affected by enforcement and reporting patterns.")
                    .font(.caption)
                    .foregroundStyle(AICTheme.secondaryText)

                Button("How this beta score works") { showMethodology = true }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AICTheme.lavender)
            }
        }
    }

    private func categoryFraction(_ count: Int) -> Double {
        let maximum = max(result.categoryCounts.map(\.count).max() ?? 0, 1)
        return Double(count) / Double(maximum)
    }

    private func color(for category: IncidentCategory) -> Color {
        switch category {
        case .assaultBattery: AICTheme.coral
        case .robbery: AICTheme.lavender
        case .theft: AICTheme.mint
        case .motorVehicleTheft: Color.cyan
        }
    }

    private func ordinal(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)th"
    }
}

private struct MethodologySheet: View {
    @Environment(\.dismiss) private var dismiss
    let result: ChicagoScanResult

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Reported Incident Exposure Index")
                        .font(.title.weight(.black))
                    Text("The local pack assigns each selected historical incident to one non-overlapping 250 m cell. Each category is independently rounded to the nearest five before the pack ships. AIC estimates a fixed 500 m circle with a deterministic 10 × 10 midpoint area calculation, then compares the rounded estimate with Chicago locations calculated by the same method. The displayed score is rounded to the nearest five.")
                    Text("Beta method")
                        .font(.headline)
                    Text("Scan coordinates are processed locally and snapped to a one-metre calculation grid. Boundary locations without a complete comparison circle are unavailable. Counts and category values are privacy-coarsened estimates, not exact totals. The pack contains no incident points, exact cell totals, residual totals, source record IDs, addresses, or dates.")
                    Text("Each selected incident contributes equally before privacy coarsening. There are no severity weights, recency weights, personal-risk probabilities, live conditions, causal claims, or cross-city comparisons. The current method is deterministic and provisional.")
                    Text("Included categories")
                        .font(.headline)
                    Text("Assault/battery, robbery, theft, and motor-vehicle theft. Ambiguous source categories are excluded.")
                    Text("Known limitations")
                        .font(.headline)
                    Text("Reported incidents are not all incidents. Reporting, classification, police activity, source revisions, geography, seasonality, and small samples can affect comparisons. A high or low score does not guarantee danger or safety.")
                    Text("Methodology version: \(result.methodologyVersion)")
                        .font(.caption.monospaced())
                        .foregroundStyle(AICTheme.secondaryText)
                }
                .padding(20)
            }
            .background(AICTheme.ink)
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}
