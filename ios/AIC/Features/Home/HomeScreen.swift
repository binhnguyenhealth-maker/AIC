import AICCore
import SwiftUI

struct HomeScreen: View {
    @ObservedObject var model: AppModel
    let onResult: (ChicagoScanResult) -> Void

    @StateObject private var locationService = LocationService()
    @State private var packSummary: PackSummary?
    @State private var packError: String?
    @State private var isScanning = false
    @State private var showManualPicker = false
    @State private var showSettings = false

    private let scanEngine = LocalScanEngine()

    var body: some View {
        ZStack {
            AICBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    scorePrompt
                    privacyStrip
                    manualReason
                    packCard
                }
                .aicPagePadding()
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: {
                    Image(systemName: "person.crop.circle")
                        .font(.title2)
                        .accessibilityLabel("Account settings")
                }
            }
        }
        .sheet(isPresented: $showManualPicker) {
            OfflinePinPicker { coordinate in
                showManualPicker = false
                scan(coordinate)
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showSettings) {
            SettingsScreen(model: model)
        }
        .task { await loadPackSummary() }
        .onChange(of: locationService.state) { _, state in
            guard case let .located(coordinate) = state else { return }
            locationService.reset()
            scan(coordinate)
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("CHICAGO / 500 M")
                .font(.caption.weight(.heavy))
                .tracking(1.7)
                .foregroundStyle(AICTheme.mint)
            Text("Ready, @\(model.username)")
                .font(.system(size: 31, weight: .black, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("Your scan point stays on this iPhone.")
                .font(.subheadline)
                .foregroundStyle(AICTheme.secondaryText)
        }
    }

    private var scorePrompt: some View {
        AICCard {
            VStack(alignment: .leading, spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(AICTheme.mint.opacity(0.16), lineWidth: 22)
                    Circle()
                        .stroke(AICTheme.mint.opacity(0.5), lineWidth: 2)
                        .padding(24)
                    Image(systemName: "location.fill")
                        .font(.system(size: 34, weight: .black))
                        .foregroundStyle(AICTheme.coral)
                }
                .frame(width: 142, height: 142)
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 7) {
                    Text("Cook this location")
                        .font(.title2.weight(.black))
                    Text("Estimate four supported incident categories for a fixed 500 m circle from privacy-coarsened local data, then compare with eligible Chicago locations.")
                        .font(.subheadline)
                        .foregroundStyle(AICTheme.secondaryText)
                }

                Button {
                    locationService.requestCurrentLocation()
                } label: {
                    Group {
                        if isScanning || isRequestingLocation {
                            HStack(spacing: 10) {
                                ProgressView().tint(AICTheme.ink)
                                Text(isScanning ? "Computing locally…" : "Finding you once…")
                            }
                        } else {
                            Label("Scan Me", systemImage: "scope")
                        }
                    }
                }
                .buttonStyle(PrimaryActionStyle())
                .disabled(isScanning || isRequestingLocation || packSummary == nil)

                Button {
                    showManualPicker = true
                } label: {
                    Label("Choose a spot manually", systemImage: "hand.tap")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .disabled(isScanning || packSummary == nil)
                .accessibilityHint("Opens the offline Chicago position picker without requesting location permission.")
            }
        }
    }

    private var privacyStrip: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.fill")
                .foregroundStyle(AICTheme.mint)
            Text("Location and incident lookup are local. AIC sends no coordinate, address, route, geographic cell, or scan history to its account service.")
                .font(.caption)
                .foregroundStyle(AICTheme.secondaryText)
        }
    }

    @ViewBuilder
    private var manualReason: some View {
        switch locationService.state {
        case .denied:
            fallbackBanner("Location permission is off. The manual picker is ready and free.")
        case .restricted:
            fallbackBanner("Location access is restricted. Use the manual Chicago picker.")
        case let .failed(message):
            fallbackBanner(message)
        default:
            EmptyView()
        }
    }

    private func fallbackBanner(_ message: String) -> some View {
        Button {
            showManualPicker = true
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "mappin.and.ellipse")
                Text(message)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
            }
            .font(.subheadline.weight(.semibold))
            .padding(16)
            .background(AICTheme.coral.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var packCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label("Chicago data pack", systemImage: packSummary == nil ? "externaldrive.badge.xmark" : "externaldrive.fill.badge.checkmark")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text("LOCAL")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(AICTheme.mint)
            }
            if let packSummary {
                Text("Historical period starts \(packSummary.periodStart) · Source through \(packSummary.sourceThroughDate)")
                    .font(.caption)
                    .foregroundStyle(AICTheme.secondaryText)
            } else if let packError {
                Text(packError)
                    .font(.caption)
                    .foregroundStyle(AICTheme.coral)
            } else {
                ProgressView("Checking pack…")
                    .font(.caption)
            }
        }
        .padding(.top, 4)
    }

    private var isRequestingLocation: Bool {
        switch locationService.state {
        case .requestingPermission, .locating: true
        default: false
        }
    }

    private func loadPackSummary() async {
        do {
            packSummary = try await scanEngine.packSummary()
            packError = nil
        } catch {
            packSummary = nil
            packError = error.localizedDescription
        }
    }

    private func scan(_ coordinate: ScanCoordinate) {
        guard !isScanning else { return }
        isScanning = true
        Task {
            defer { isScanning = false }
            do {
                onResult(try await scanEngine.scan(at: coordinate))
            } catch {
                model.present(error.localizedDescription)
            }
        }
    }
}
