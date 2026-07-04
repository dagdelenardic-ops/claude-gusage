import XCTest
@testable import ClaudeUsageBar

final class NotificationServiceTests: XCTestCase {
    func testNoAlertsWhenAllOff() {
        let alerts = crossedThresholds(
            threshold5h: 0, threshold7d: 0, thresholdExtra: 0,
            previous5h: 40, previous7d: 30, previousExtra: 20,
            current5h: 90, current7d: 85, currentExtra: 80
        )
        XCTAssertTrue(alerts.isEmpty)
    }

    func testOnly5hFires() {
        let alerts = crossedThresholds(
            threshold5h: 80, threshold7d: 0, thresholdExtra: 0,
            previous5h: 70, previous7d: 50, previousExtra: 10,
            current5h: 85, current7d: 90, currentExtra: 50
        )
        XCTAssertEqual(alerts, [ThresholdAlert(window: "Current Session", pct: 85)])
    }

    func testOnly7dFires() {
        let alerts = crossedThresholds(
            threshold5h: 0, threshold7d: 80, thresholdExtra: 0,
            previous5h: 70, previous7d: 70, previousExtra: 10,
            current5h: 85, current7d: 85, currentExtra: 50
        )
        XCTAssertEqual(alerts, [ThresholdAlert(window: "All Models", pct: 85)])
    }

    func testOnlyExtraFires() {
        let alerts = crossedThresholds(
            threshold5h: 0, threshold7d: 0, thresholdExtra: 50,
            previous5h: 70, previous7d: 70, previousExtra: 40,
            current5h: 85, current7d: 85, currentExtra: 60
        )
        XCTAssertEqual(alerts, [ThresholdAlert(window: "Extra usage", pct: 60)])
    }

    func testAllThreeFireSimultaneously() {
        let alerts = crossedThresholds(
            threshold5h: 80, threshold7d: 80, thresholdExtra: 50,
            previous5h: 70, previous7d: 70, previousExtra: 40,
            current5h: 85, current7d: 90, currentExtra: 60
        )
        XCTAssertEqual(alerts, [
            ThresholdAlert(window: "Current Session", pct: 85),
            ThresholdAlert(window: "All Models", pct: 90),
            ThresholdAlert(window: "Extra usage", pct: 60),
        ])
    }

    func testNoAlertWhenStayingAbove() {
        let alerts = crossedThresholds(
            threshold5h: 80, threshold7d: 80, thresholdExtra: 50,
            previous5h: 85, previous7d: 90, previousExtra: 60,
            current5h: 88, current7d: 92, currentExtra: 65
        )
        XCTAssertTrue(alerts.isEmpty)
    }

    func testNoAlertWhenStayingBelow() {
        let alerts = crossedThresholds(
            threshold5h: 80, threshold7d: 80, thresholdExtra: 50,
            previous5h: 50, previous7d: 60, previousExtra: 30,
            current5h: 70, current7d: 75, currentExtra: 45
        )
        XCTAssertTrue(alerts.isEmpty)
    }

    func testExactThresholdTriggers() {
        let alerts = crossedThresholds(
            threshold5h: 80, threshold7d: 0, thresholdExtra: 0,
            previous5h: 79, previous7d: 50, previousExtra: 10,
            current5h: 80, current7d: 50, currentExtra: 10
        )
        XCTAssertEqual(alerts, [ThresholdAlert(window: "Current Session", pct: 80)])
    }

    func testFirstPollFiresWhenAlreadyAboveThreshold() {
        let alerts = crossedThresholds(
            threshold5h: 25, threshold7d: 5, thresholdExtra: 0,
            previous5h: 0, previous7d: 0, previousExtra: 0,
            current5h: 60, current7d: 40, currentExtra: 10
        )
        XCTAssertEqual(alerts, [
            ThresholdAlert(window: "Current Session", pct: 60),
            ThresholdAlert(window: "All Models", pct: 40),
        ])
    }

    func testFirstPollDoesNotFireWhenBelowThreshold() {
        let alerts = crossedThresholds(
            threshold5h: 80, threshold7d: 80, thresholdExtra: 0,
            previous5h: 0, previous7d: 0, previousExtra: 0,
            current5h: 30, current7d: 50, currentExtra: 10
        )
        XCTAssertTrue(alerts.isEmpty)
    }

    func testDifferentThresholdsPerWindow() {
        let alerts = crossedThresholds(
            threshold5h: 90, threshold7d: 50, thresholdExtra: 70,
            previous5h: 85, previous7d: 45, previousExtra: 65,
            current5h: 95, current7d: 55, currentExtra: 75
        )
        XCTAssertEqual(alerts, [
            ThresholdAlert(window: "Current Session", pct: 95),
            ThresholdAlert(window: "All Models", pct: 55),
            ThresholdAlert(window: "Extra usage", pct: 75),
        ])
    }

    // MARK: - Critical scoped-limit alerts

    private func limit(
        id: String,
        percent: Double?,
        severity: String,
        isActive: Bool? = true
    ) -> UsageLimit {
        // `id` is derived from kind|group|scope, so drive it through `kind`.
        UsageLimit(
            kind: id,
            group: nil,
            percent: percent,
            severity: severity,
            resetsAt: nil,
            scope: nil,
            isActive: isActive
        )
    }

    func testCriticalLimitAlertsOnFirstEntry() {
        let (alerts, criticalNow) = newlyCriticalScopedLimits(
            limits: [limit(id: "fable", percent: 100, severity: "critical")],
            alreadyNotified: []
        )
        XCTAssertEqual(alerts, [CriticalLimitAlert(id: "fable||", label: "fable", pct: 100)])
        XCTAssertEqual(criticalNow, ["fable||"])
    }

    func testCriticalLimitDoesNotRepeatWhileStillCritical() {
        let (alerts, criticalNow) = newlyCriticalScopedLimits(
            limits: [limit(id: "fable", percent: 100, severity: "critical")],
            alreadyNotified: ["fable||"]
        )
        XCTAssertTrue(alerts.isEmpty)
        XCTAssertEqual(criticalNow, ["fable||"])
    }

    func testNonCriticalLimitDoesNotAlert() {
        let (alerts, criticalNow) = newlyCriticalScopedLimits(
            limits: [limit(id: "fable", percent: 60, severity: "normal")],
            alreadyNotified: []
        )
        XCTAssertTrue(alerts.isEmpty)
        XCTAssertTrue(criticalNow.isEmpty)
    }

    func testInactiveCriticalLimitIsIgnored() {
        let (alerts, criticalNow) = newlyCriticalScopedLimits(
            limits: [limit(id: "fable", percent: 100, severity: "critical", isActive: false)],
            alreadyNotified: []
        )
        XCTAssertTrue(alerts.isEmpty)
        XCTAssertTrue(criticalNow.isEmpty)
    }

    func testLimitForgottenAfterDroppingOutOfCritical() {
        // Was critical (tracked), now back to normal — state clears so it can
        // alert again on a future re-entry.
        let (alerts, criticalNow) = newlyCriticalScopedLimits(
            limits: [limit(id: "fable", percent: 40, severity: "normal")],
            alreadyNotified: ["fable||"]
        )
        XCTAssertTrue(alerts.isEmpty)
        XCTAssertTrue(criticalNow.isEmpty)
    }

    func testReEntryAlertsAgainAfterRecovery() {
        // State was cleared after recovery; a fresh critical reading alerts.
        let (alerts, criticalNow) = newlyCriticalScopedLimits(
            limits: [limit(id: "fable", percent: 100, severity: "critical")],
            alreadyNotified: []
        )
        XCTAssertEqual(alerts.map(\.id), ["fable||"])
        XCTAssertEqual(criticalNow, ["fable||"])
    }

    func testOnlyNewlyCriticalLimitsAlertWhenMixed() {
        let (alerts, criticalNow) = newlyCriticalScopedLimits(
            limits: [
                limit(id: "fable", percent: 100, severity: "critical"),
                limit(id: "opus", percent: 100, severity: "critical"),
                limit(id: "sonnet", percent: 50, severity: "normal"),
            ],
            alreadyNotified: ["fable||"]
        )
        XCTAssertEqual(alerts.map(\.id), ["opus||"])
        XCTAssertEqual(criticalNow, ["fable||", "opus||"])
    }

    func testCriticalLimitWithoutPercentStillAlerts() {
        let (alerts, _) = newlyCriticalScopedLimits(
            limits: [limit(id: "fable", percent: nil, severity: "critical")],
            alreadyNotified: []
        )
        XCTAssertEqual(alerts.first?.pct, nil)
        XCTAssertEqual(alerts.first?.id, "fable||")
    }

    // MARK: - Weekly reset reminder

    private let referenceNow = Date(timeIntervalSince1970: 1_700_000_000)

    func testWeeklyResetDoesNotFireWithoutResetDate() {
        XCTAssertFalse(shouldNotifyWeeklyReset(
            resetsAt: nil,
            now: referenceNow,
            lastNotifiedReset: nil
        ))
    }

    func testWeeklyResetDoesNotFireOutsideWindow() {
        // 11 hours away — still outside the 10h lead window.
        let reset = referenceNow.addingTimeInterval(11 * 3600)
        XCTAssertFalse(shouldNotifyWeeklyReset(
            resetsAt: reset,
            now: referenceNow,
            lastNotifiedReset: nil
        ))
    }

    func testWeeklyResetFiresExactlyAtWindowBoundary() {
        let reset = referenceNow.addingTimeInterval(10 * 3600)
        XCTAssertTrue(shouldNotifyWeeklyReset(
            resetsAt: reset,
            now: referenceNow,
            lastNotifiedReset: nil
        ))
    }

    func testWeeklyResetFiresInsideWindow() {
        let reset = referenceNow.addingTimeInterval(5 * 3600)
        XCTAssertTrue(shouldNotifyWeeklyReset(
            resetsAt: reset,
            now: referenceNow,
            lastNotifiedReset: nil
        ))
    }

    func testWeeklyResetDoesNotFireAfterReset() {
        // Reset already passed.
        let reset = referenceNow.addingTimeInterval(-60)
        XCTAssertFalse(shouldNotifyWeeklyReset(
            resetsAt: reset,
            now: referenceNow,
            lastNotifiedReset: nil
        ))
    }

    func testWeeklyResetDoesNotRepeatForSameReset() {
        let reset = referenceNow.addingTimeInterval(5 * 3600)
        XCTAssertFalse(shouldNotifyWeeklyReset(
            resetsAt: reset,
            now: referenceNow,
            lastNotifiedReset: reset
        ))
    }

    func testWeeklyResetFiresAgainForNewReset() {
        // A previous week's reset was announced; a new reset enters the window.
        let previousReset = referenceNow.addingTimeInterval(-7 * 24 * 3600)
        let newReset = referenceNow.addingTimeInterval(8 * 3600)
        XCTAssertTrue(shouldNotifyWeeklyReset(
            resetsAt: newReset,
            now: referenceNow,
            lastNotifiedReset: previousReset
        ))
    }
}
