import Foundation

enum AICDistanceSystem: Equatable {
    case us
    case metric

    var compactRadius: String {
        switch self {
        case .us: "0.3 MI"
        case .metric: "500 M"
        }
    }

    var radiusTitle: String {
        switch self {
        case .us: "Scan a 0.3-mile radius"
        case .metric: "Scan a 500 m radius"
        }
    }

    var radiusDescription: String {
        switch self {
        case .us: "about 0.3 mi (1,640 ft)"
        case .metric: "500 m"
        }
    }

    var accessibilityRadius: String {
        switch self {
        case .us: "about zero point three miles, or one thousand six hundred forty feet"
        case .metric: "500 meters"
        }
    }
}

enum AICMeasurementPreference: String, CaseIterable, Identifiable {
    case automatic
    case us
    case metric

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: "Automatic"
        case .us: "U.S."
        case .metric: "Metric"
        }
    }

    func resolvedSystem(for locale: Locale = .autoupdatingCurrent) -> AICDistanceSystem {
        switch self {
        case .automatic:
            locale.measurementSystem == .us ? .us : .metric
        case .us:
            .us
        case .metric:
            .metric
        }
    }
}
