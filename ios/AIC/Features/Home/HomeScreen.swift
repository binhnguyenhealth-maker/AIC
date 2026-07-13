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
    @State private var completedScans = 0

    private let scanEngine = LocalScanEngine()

    var body: some View {
        ZStack {
            AICBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
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
        .sensoryFeedback(.success, trigger: completedScans)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CHICAGO  ·  500 M  ·  ON-DEVICE")
                .font(.caption.weight(.heavy))
                .tracking(1.7)
                .foregroundStyle(AICTheme.mint)
            Text("Am I cooked, fam?")
                .font(.system(size: 29, weight: .black, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("Historical reported-incident data. Never a live danger scan.")
                .font(.subheadline)
                .foregroundStyle(AICTheme.secondaryText)
        }
    }

    private var scorePrompt: some View {
        AICCard {
            VStack(alignment: .leading, spacing: 16) {
                RadarScanView(state: radarState)
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 7) {
                    Text(radarState == .idle ? "Scan the 500 m around you" : radarStatusTitle)
                        .font(.title2.weight(.black))
                        .contentTransition(.numericText())
                    Text("Check nearby reported incidents using the Chicago data pack stored on your iPhone.")
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
                                Text(isScanning ? "Scanning the area…" : "Finding your area…")
                            }
                        } else {
                            Label("Scan My Area", systemImage: "scope")
                        }
                    }
                }
                .buttonStyle(PrimaryActionStyle())
                .disabled(isScanning || isRequestingLocation || packSummary == nil)

                Button {
                    showManualPicker = true
                } label: {
                    Label("Choose another spot", systemImage: "hand.tap")
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
            Text("Your point and scan history stay on this iPhone. AIC sends no coordinate, address, route, or geographic cell to its account service.")
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

    private var radarState: RadarScanView.State {
        if isScanning { return .scanning }
        if isRequestingLocation { return .locating }
        return .idle
    }

    private var radarStatusTitle: String {
        switch radarState {
        case .idle: "Scan the 500 m around you"
        case .locating: "Locking onto your area"
        case .scanning: "Scanning reported history"
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
                async let result = scanEngine.scan(at: coordinate)
                async let minimumSweep: Void = Task.sleep(for: .milliseconds(1_100))
                let scanResult = try await result
                try await minimumSweep
                completedScans += 1
                onResult(scanResult)
            } catch {
                model.present(error.localizedDescription)
            }
        }
    }
}
