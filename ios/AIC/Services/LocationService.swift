import AICCore
@preconcurrency import CoreLocation
import Foundation

@MainActor
final class LocationService: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    enum State: Equatable {
        case idle
        case requestingPermission
        case locating
        case located(ScanCoordinate)
        case denied
        case restricted
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    private var manager: CLLocationManager?

    func requestCurrentLocation() {
        // CLLocationManager is intentionally created only after the user taps Scan My Area.
        let manager = manager ?? CLLocationManager()
        self.manager = manager
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters

        switch manager.authorizationStatus {
        case .notDetermined:
            state = .requestingPermission
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            state = .locating
            manager.requestLocation()
        case .denied:
            state = .denied
        case .restricted:
            state = .restricted
        @unknown default:
            state = .failed("Location access is unavailable.")
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            state = .locating
            manager.requestLocation()
        case .denied:
            state = .denied
        case .restricted:
            state = .restricted
        case .notDetermined:
            state = .requestingPermission
        @unknown default:
            state = .failed("Location access is unavailable.")
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            state = .failed("No current location was returned. Use the manual Chicago picker.")
            return
        }
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 250 else {
            state = .failed("Location accuracy is too low for this scan radius. Use the manual Chicago picker.")
            return
        }
        guard abs(location.timestamp.timeIntervalSinceNow) <= 60 else {
            state = .failed("The available location is stale. Use the manual Chicago picker or try again.")
            return
        }
        state = .located(ScanCoordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        ))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        state = .failed("Location could not be read. Use the manual Chicago picker.")
    }

    func reset() {
        state = .idle
    }

    static func offersManualFallback(for state: State) -> Bool {
        switch state {
        case .denied, .restricted, .failed: true
        default: false
        }
    }
}
