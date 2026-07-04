import XCTest
@testable import ClaudeUsageBar

final class UsageLimitsTests: XCTestCase {
    /// A trimmed but structurally faithful copy of a real usage response.
    private let realJSON = """
    {
      "five_hour": {"utilization": 8.0, "resets_at": "2026-07-04T14:59:59.732177+00:00"},
      "seven_day": {"utilization": 71.0, "resets_at": "2026-07-05T18:59:59.732198+00:00"},
      "seven_day_opus": null,
      "seven_day_sonnet": null,
      "seven_day_omelette": null,
      "extra_usage": {"is_enabled": false, "monthly_limit": 500, "used_credits": 0.0, "utilization": 0.0},
      "limits": [
        {"kind": "session", "group": "session", "percent": 8, "severity": "normal", "resets_at": "2026-07-04T14:59:59.732177+00:00", "scope": null, "is_active": false},
        {"kind": "weekly_all", "group": "weekly", "percent": 71, "severity": "normal", "resets_at": "2026-07-05T18:59:59.732198+00:00", "scope": null, "is_active": false},
        {"kind": "weekly_scoped", "group": "weekly", "percent": 100, "severity": "critical", "resets_at": "2026-07-05T18:59:59.732536+00:00", "scope": {"model": {"id": null, "display_name": "Fable"}, "surface": null}, "is_active": true}
      ]
    }
    """

    private func decode() throws -> UsageResponse {
        let data = Data(realJSON.utf8)
        return try JSONDecoder().decode(UsageResponse.self, from: data)
    }

    func testDecodesAllLimits() throws {
        let usage = try decode()
        XCTAssertEqual(usage.limits?.count, 3)
    }

    func testScopedLimitsFilterOutUnscopedEntries() throws {
        // session + weekly_all have no scope; only the Fable-scoped one should remain.
        let usage = try decode()
        XCTAssertEqual(usage.scopedLimits.count, 1)
    }

    func testFableScopedLimitIsSurfaced() throws {
        let usage = try decode()
        let fable = try XCTUnwrap(usage.scopedLimits.first)
        XCTAssertEqual(fable.displayLabel, "Fable")
        XCTAssertEqual(fable.percent, 100)
        XCTAssertEqual(fable.percentText, "100%")
        XCTAssertTrue(fable.isCritical)
        XCTAssertEqual(fable.isActive, true)
        XCTAssertNotNil(fable.resetsAtDate)
    }

    func testLimitsSurviveReconciliation() throws {
        // Reconciliation must not drop the limits array.
        let usage = try decode()
        let reconciled = usage.reconciled(with: nil)
        XCTAssertEqual(reconciled.scopedLimits.first?.displayLabel, "Fable")
    }

    func testMissingLimitsDecodesToNil() throws {
        let json = #"{"five_hour": {"utilization": 5.0, "resets_at": null}}"#
        let usage = try JSONDecoder().decode(UsageResponse.self, from: Data(json.utf8))
        XCTAssertNil(usage.limits)
        XCTAssertTrue(usage.scopedLimits.isEmpty)
    }
}
