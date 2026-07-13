import XCTest
@testable import AICCore

final class ReceiptPrivacyTests: XCTestCase {
    private let result = ChicagoScanResult(
        cookedScore: 75,
        chicagoPercentile: 73.4,
        estimatedIncidentCount: 42,
        categoryCounts: [
            CategoryCount(category: .assaultBattery, count: 12),
            CategoryCount(category: .robbery, count: 6),
            CategoryCount(category: .theft, count: 20),
            CategoryCount(category: .motorVehicleTheft, count: 4)
        ],
        neighborhood: "Near West Side",
        sourceThroughDate: "2026-06-30",
        periodStart: "2025-07-01",
        methodologyVersion: "beta-cell250-q5-area-v3"
    )

    func testReceiptSchemaCannotEncodePreciseLocation() throws {
        let payload = ReceiptComposer.make(
            result: result,
            locationMode: .neighborhood
        )
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(payload))
        XCTAssertEqual(payload.schemaVersion, 2)
        XCTAssertEqual(payload.estimatedIncidentCount, 42)
        XCTAssertEqual(ReceiptPrivacyAudit.forbiddenKeys(in: object), [])
    }

    func testLocationCanBeHidden() {
        let payload = ReceiptComposer.make(
            result: result,
            locationMode: .hidden
        )
        XCTAssertNil(payload.locationLabel)
    }

    func testGuestReceiptCannotEncodeIdentityFields() throws {
        let payload = ReceiptComposer.make(
            result: result,
            locationMode: .neighborhood
        )

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any]
        )
        XCTAssertNil(object["username"])
        XCTAssertNil(object["account"])
        XCTAssertNil(object["account_id"])
        XCTAssertEqual(ReceiptPrivacyAudit.forbiddenKeys(in: object), [])
    }

    func testPrivacyAuditRejectsIdentityFields() {
        let object: [String: Any] = [
            "username": "guest",
            "nested": ["account_id": "account-1"]
        ]

        XCTAssertEqual(
            ReceiptPrivacyAudit.forbiddenKeys(in: object),
            Set(["username", "account_id"])
        )
    }

    func testNeighborhoodOffFallsBackToCityOnly() {
        let payload = ReceiptComposer.make(
            result: result,
            locationMode: .cityOnly
        )
        XCTAssertEqual(payload.locationLabel, "Chicago")
    }

    func testBroadBucketDoesNotContainExactTimeOrDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = Date(timeIntervalSince1970: 1_719_000_000)
        let bucket = ReceiptComposer.broadTimeBucket(for: date, calendar: calendar)
        XCTAssertFalse(bucket.contains(":"))
        XCTAssertFalse(bucket.contains("2024"))
        XCTAssertTrue(["morning", "afternoon", "evening", "night"].contains { bucket.contains($0) })
    }
}
