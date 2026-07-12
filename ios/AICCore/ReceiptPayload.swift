import Foundation

public enum ReceiptLocationMode: String, Codable, CaseIterable, Sendable {
    case neighborhood
    case cityOnly = "city_only"
    case hidden

    public var displayName: String {
        switch self {
        case .neighborhood: "Neighborhood"
        case .cityOnly: "Chicago only"
        case .hidden: "Hide location"
        }
    }
}

public struct CookedReceiptPayload: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let username: String?
    public let locationMode: ReceiptLocationMode
    public let locationLabel: String?
    public let broadTimeBucket: String
    public let cookedScore: Int
    public let chicagoPercentile: Int
    public let mainCategory: String
    public let estimatedIncidentCount: Int
    public let sourceThroughDate: String
    public let disclaimer: String

    public init(
        username: String?,
        locationMode: ReceiptLocationMode,
        locationLabel: String?,
        broadTimeBucket: String,
        cookedScore: Int,
        chicagoPercentile: Int,
        mainCategory: String,
        estimatedIncidentCount: Int,
        sourceThroughDate: String
    ) {
        schemaVersion = 2
        self.username = username
        self.locationMode = locationMode
        self.locationLabel = locationLabel
        self.broadTimeBucket = broadTimeBucket
        self.cookedScore = cookedScore
        self.chicagoPercentile = chicagoPercentile
        self.mainCategory = mainCategory
        self.estimatedIncidentCount = estimatedIncidentCount
        self.sourceThroughDate = sourceThroughDate
        disclaimer = ChicagoScanResult.requiredDisclaimer
    }
}

public enum ReceiptComposer {
    public static func make(
        result: ChicagoScanResult,
        username: String,
        showUsername: Bool,
        locationMode: ReceiptLocationMode,
        date: Date = Date(),
        calendar: Calendar = .current
    ) -> CookedReceiptPayload {
        let label: String?
        switch locationMode {
        case .neighborhood:
            label = result.neighborhood
        case .cityOnly:
            label = "Chicago"
        case .hidden:
            label = nil
        }

        return CookedReceiptPayload(
            username: showUsername ? UsernamePolicy.normalize(username) : nil,
            locationMode: locationMode,
            locationLabel: label,
            broadTimeBucket: broadTimeBucket(for: date, calendar: calendar),
            cookedScore: result.cookedScore,
            chicagoPercentile: Int(result.chicagoPercentile.rounded()),
            mainCategory: result.mainCategory.category.shortName,
            estimatedIncidentCount: result.estimatedIncidentCount,
            sourceThroughDate: result.sourceThroughDate
        )
    }

    public static func broadTimeBucket(for date: Date, calendar: Calendar = .current) -> String {
        let weekday = calendar.shortWeekdaySymbols[calendar.component(.weekday, from: date) - 1]
        let hour = calendar.component(.hour, from: date)
        let period: String
        switch hour {
        case 5 ..< 12: period = "morning"
        case 12 ..< 17: period = "afternoon"
        case 17 ..< 22: period = "evening"
        default: period = "night"
        }
        return "\(weekday) \(period)"
    }
}

public enum ReceiptPrivacyAudit {
    public static let forbiddenEncodedKeys: Set<String> = [
        "latitude", "longitude", "coordinate", "coordinates", "address", "route",
        "pin", "cell", "cell_id", "scan_id", "timestamp", "exact_time",
        "contributingincidentcount", "exactincidentcount", "exact_count", "cell_total", "residual_total"
    ]

    public static func forbiddenKeys(in encodedObject: Any) -> Set<String> {
        var found = Set<String>()
        inspect(encodedObject, found: &found)
        return found
    }

    private static func inspect(_ value: Any, found: inout Set<String>) {
        if let dictionary = value as? [String: Any] {
            for (key, child) in dictionary {
                if forbiddenEncodedKeys.contains(key.lowercased()) {
                    found.insert(key.lowercased())
                }
                inspect(child, found: &found)
            }
        } else if let array = value as? [Any] {
            array.forEach { inspect($0, found: &found) }
        }
    }
}
