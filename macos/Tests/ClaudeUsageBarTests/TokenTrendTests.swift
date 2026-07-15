import XCTest
@testable import ClaudeUsageBar

final class TokenTrendTests: XCTestCase {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2 // Monday — deterministic week boundary
        return c
    }

    private func rec(_ k: String, _ iso: String, _ model: String = "claude-opus-4-8",
                     _ proj: String = "/P", counts: TokenCounts) -> UsageRecord {
        UsageRecord(timestamp: UsageBucket.parseResetDate(from: iso)!,
                    model: model, project: proj, counts: counts, dedupKey: k)
    }

    func testDailyFillsMissingDaysOldestFirst() {
        var s = TokenUsageStore()
        // 2026-07-15 is a Wednesday. Days with data: 13 and 15; 09..12 and 14 empty.
        s.ingest(rec("1", "2026-07-13T10:00:00Z", counts: TokenCounts(input: 1_000_000)), calendar: utc)
        s.ingest(rec("2", "2026-07-15T08:00:00Z", counts: TokenCounts(output: 1_000_000)), calendar: utc)
        let now = UsageBucket.parseResetDate(from: "2026-07-15T12:00:00Z")!

        let series = TokenTrend.daily(from: s, days: 7, now: now, calendar: utc, pricing: TokenPricing())

        XCTAssertEqual(series.count, 7)
        XCTAssertEqual(series.first?.day, "2026-07-09")          // oldest first
        XCTAssertEqual(series.last?.day, "2026-07-15")           // today last
        XCTAssertEqual(series.first?.counts.total, 0)            // empty day is zero
        XCTAssertEqual(series[4].day, "2026-07-13")
        XCTAssertEqual(series[4].counts.total, 1_000_000)
        XCTAssertEqual(series[4].cost, 5.0, accuracy: 0.001)     // opus 1M input × $5/MTok
        XCTAssertEqual(series.last!.cost, 25.0, accuracy: 0.001) // opus 1M output × $25/MTok
    }

    func testDailyExcludesUnpricedModelFromCostAndFlags() {
        var s = TokenUsageStore()
        s.ingest(rec("1", "2026-07-15T08:00:00Z", counts: TokenCounts(input: 1_000_000)), calendar: utc)
        s.ingest(rec("2", "2026-07-15T09:00:00Z", "<synthetic>", counts: TokenCounts(input: 500)), calendar: utc)
        let now = UsageBucket.parseResetDate(from: "2026-07-15T12:00:00Z")!

        let today = TokenTrend.daily(from: s, days: 1, now: now, calendar: utc, pricing: TokenPricing()).last!
        XCTAssertEqual(today.counts.total, 1_000_500)    // tokens are still counted
        XCTAssertEqual(today.cost, 5.0, accuracy: 0.001) // unpriced model excluded from $
        XCTAssertTrue(today.hasUnknownModel)
    }

    func testWeekComparisonUsesCalendarWeekBoundary() {
        var s = TokenUsageStore()
        // 2026-07-15 is a Wednesday; week Mon 13 – Sun 19. Previous week Mon 6 – Sun 12.
        s.ingest(rec("1", "2026-07-14T10:00:00Z", counts: TokenCounts(input: 1_000_000)), calendar: utc)  // this week: $5
        s.ingest(rec("2", "2026-07-12T10:00:00Z", counts: TokenCounts(input: 2_000_000)), calendar: utc)  // last week (Sunday): $10
        s.ingest(rec("3", "2026-07-05T10:00:00Z", counts: TokenCounts(input: 8_000_000)), calendar: utc)  // 2 weeks ago: not included
        let now = UsageBucket.parseResetDate(from: "2026-07-15T12:00:00Z")!

        let c = TokenTrend.weekComparison(from: s, now: now, calendar: utc, pricing: TokenPricing())
        XCTAssertEqual(c.currentCost, 5.0, accuracy: 0.001)
        XCTAssertEqual(c.previousCost, 10.0, accuracy: 0.001)
        XCTAssertEqual(c.currentTokens, 1_000_000)
        XCTAssertEqual(c.previousTokens, 2_000_000)
        XCTAssertEqual(c.costDeltaRatio!, -0.5, accuracy: 0.001)
    }

    func testMonthComparisonAndNewPeriod() {
        var s = TokenUsageStore()
        s.ingest(rec("1", "2026-07-10T10:00:00Z", counts: TokenCounts(input: 1_000_000)), calendar: utc)  // July: $5
        let now = UsageBucket.parseResetDate(from: "2026-07-15T12:00:00Z")!

        let c = TokenTrend.monthComparison(from: s, now: now, calendar: utc, pricing: TokenPricing())
        XCTAssertEqual(c.currentCost, 5.0, accuracy: 0.001)
        XCTAssertEqual(c.previousCost, 0.0, accuracy: 0.001)  // June empty
        XCTAssertNil(c.costDeltaRatio)                         // previous 0 → "new"
    }
}
