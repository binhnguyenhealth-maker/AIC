import Foundation

public enum IncidentCategory: String, Codable, CaseIterable, Sendable {
    case assaultBattery = "assault_battery"
    case robbery
    case theft
    case motorVehicleTheft = "motor_vehicle_theft"

    public var displayName: String {
        switch self {
        case .assaultBattery: "Assault & battery"
        case .robbery: "Robbery"
        case .theft: "Theft"
        case .motorVehicleTheft: "Motor-vehicle theft"
        }
    }

    public var shortName: String {
        switch self {
        case .assaultBattery: "Assault"
        case .robbery: "Robbery"
        case .theft: "Theft"
        case .motorVehicleTheft: "Vehicle theft"
        }
    }
}

public struct ScanCoordinate: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public var isGeographicallyValid: Bool {
        (-90 ... 90).contains(latitude) && (-180 ... 180).contains(longitude)
    }
}

public struct CategoryCount: Codable, Equatable, Identifiable, Sendable {
    public var id: String { category.rawValue }
    public let category: IncidentCategory
    public let count: Int

    public init(category: IncidentCategory, count: Int) {
        self.category = category
        self.count = count
    }
}

public enum PackFreshnessState: String, Codable, Equatable, Sendable {
    case withinUpdateWindow
    case updateDueSoon
    case blocked
}

public struct PackFreshnessSummary: Codable, Equatable, Sendable {
    public let sourceThroughDate: String
    public let periodStart: String
    public let sourceRetrievedAt: Date
    public let freshUntilDate: String
    public let expiresAtDate: String
    public let state: PackFreshnessState
    public let daysSinceSourceThrough: Int
    public let daysUntilCutoff: Int

    public init(
        sourceThroughDate: String,
        periodStart: String,
        sourceRetrievedAt: Date,
        freshUntilDate: String,
        expiresAtDate: String,
        state: PackFreshnessState,
        daysSinceSourceThrough: Int,
        daysUntilCutoff: Int
    ) {
        self.sourceThroughDate = sourceThroughDate
        self.periodStart = periodStart
        self.sourceRetrievedAt = sourceRetrievedAt
        self.freshUntilDate = freshUntilDate
        self.expiresAtDate = expiresAtDate
        self.state = state
        self.daysSinceSourceThrough = daysSinceSourceThrough
        self.daysUntilCutoff = daysUntilCutoff
    }
}

public struct ChicagoScanResult: Codable, Equatable, Sendable {
    public let cookedScore: Int
    public let chicagoPercentile: Double
    public let estimatedIncidentCount: Int
    public let categoryCounts: [CategoryCount]
    public let neighborhood: String
    public let sourceThroughDate: String
    public let periodStart: String
    public let methodologyVersion: String

    public init(
        cookedScore: Int,
        chicagoPercentile: Double,
        estimatedIncidentCount: Int,
        categoryCounts: [CategoryCount],
        neighborhood: String,
        sourceThroughDate: String,
        periodStart: String,
        methodologyVersion: String
    ) {
        self.cookedScore = cookedScore
        self.chicagoPercentile = chicagoPercentile
        self.estimatedIncidentCount = estimatedIncidentCount
        self.categoryCounts = categoryCounts
        self.neighborhood = neighborhood
        self.sourceThroughDate = sourceThroughDate
        self.periodStart = periodStart
        self.methodologyVersion = methodologyVersion
    }

    public var mainCategory: CategoryCount {
        categoryCounts.max { lhs, rhs in
            if lhs.count == rhs.count {
                let leftIndex = IncidentCategory.allCases.firstIndex(of: lhs.category) ?? 0
                let rightIndex = IncidentCategory.allCases.firstIndex(of: rhs.category) ?? 0
                return leftIndex > rightIndex
            }
            return lhs.count < rhs.count
        } ?? CategoryCount(category: .theft, count: 0)
    }

    public static let requiredDisclaimer = "Cooked Score is a historical data index that compares reported-incident concentration around this location with eligible Chicago comparison locations. It is not a live safety assessment or personal-risk prediction."
    public static let estimateDisclosure = "Incident counts are privacy-coarsened estimates, not exact totals."
}

public enum ManualLocationFallback: Equatable, Sendable {
    case unavailable
    case available(reason: Reason)

    public enum Reason: Equatable, Sendable {
        case permissionDenied
        case permissionRestricted
        case locationFailure
    }
}

public struct AuthSession: Codable, Equatable, Sendable {
    public let accountID: String
    public let accessToken: String
    public let refreshToken: String
    public let accessTokenExpiresAt: Date
    public let username: String?

    public init(
        accountID: String,
        accessToken: String,
        refreshToken: String,
        accessTokenExpiresAt: Date,
        username: String?
    ) {
        self.accountID = accountID
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accessTokenExpiresAt = accessTokenExpiresAt
        self.username = username
    }
}
