import AICCore
import SwiftUI

struct HomeScreen: View {
    @ObservedObject var model: AppModel
    let onResult: (ChicagoScanResult) -> Void

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var locationService = LocationService()
    @State private var packSummary: PackSummary?
    @State private var packError: String?
    @State private var isScanning = false
    @State private var showManualPicker = false
    @State private var showSettings = false
    @State private var selectedPassport: DataPassportSelection?
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
                }
                .aicPagePadding()
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.title2)
                        .accessibilityLabel("Settings")
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
        .sheet(item: $selectedPassport) { selection in
            DataPassportView(summary: selection.summary)
                .presentationDetents([.large])
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await loadPackSummary()
        }
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
            Text("CHICAGO  ·  \(model.distanceSystem.compactRadius)  ·  ON-DEVICE")
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
                RadarScanView(state: radarState, distanceSystem: model.distanceSystem)
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 7) {
                    Text(radarState == .idle ? model.distanceSystem.radiusTitle : radarStatusTitle)
                        .font(.title2.weight(.black))
                        .contentTransition(.numericText())
                    Text("Check nearby reported incidents using the Chicago data pack stored on your iPhone.")
                        .font(.subheadline)
                        .foregroundStyle(AICTheme.secondaryText)
                }

                dataHorizon

                Button {
                    locationService.requestCurrentLocation()
                } label: {
                    Group {
                        if isScanning || isRequestingLocation {
                            HStack(spacing: 10) {
                                ProgressView().tint(AICTheme.ink)
                                Text(isScanning ? "Scanning the area…" : "Finding your area…")
                            }
                        } else if packSummary?.state == .blocked {
                            Label("Scans Paused", systemImage: "pause.circle.fill")
                        } else {
                            Label("Scan My Area", systemImage: "scope")
                        }
                    }
                }
                .buttonStyle(PrimaryActionStyle())
                .disabled(isScanning || isRequestingLocation || !isPackUsable)

                Button {
                    showManualPicker = true
                } label: {
                    Label("Choose another spot", systemImage: "hand.tap")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .disabled(isScanning || !isPackUsable)
                .accessibilityHint("Opens the offline Chicago position picker without requesting location permission.")
            }
        }
    }

    private var privacyStrip: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.fill")
                .foregroundStyle(AICTheme.mint)
            Text("Your point and scan history stay on this iPhone. AIC sends no coordinate, address, route, or geographic cell to AIC.")
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

    @ViewBuilder
    private var dataHorizon: some View {
        if let packSummary {
            DataHorizonView(summary: packSummary) {
                selectedPassport = DataPassportSelection(summary: packSummary)
            }
        } else if let packError {
            DataHorizonErrorView(message: packError)
        } else {
            HStack(spacing: 10) {
                ProgressView().tint(AICTheme.lavender)
                Text("Checking data horizon…")
                    .font(.caption.weight(.bold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var isPackUsable: Bool {
        guard let packSummary else { return false }
        return packSummary.state != .blocked
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
        case .idle: model.distanceSystem.radiusTitle
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
        guard !isScanning, isPackUsable else { return }
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
                if error as? ChicagoPackError == .packUpdateRequired {
                    await loadPackSummary()
                }
                model.present(error.localizedDescription)
            }
        }
    }
}
