import XCTest
@testable import ClaudeUsageBar

final class TokenTrendTests: XCTestCase {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2 // Pazartesi — deterministik hafta sınırı
        return c
    }

    private func rec(_ k: String, _ iso: String, _ model: String = "claude-opus-4-8",
                     _ proj: String = "/P", counts: TokenCounts) -> UsageRecord {
        UsageRecord(timestamp: UsageBucket.parseResetDate(from: iso)!,
                    model: model, project: proj, counts: counts, dedupKey: k)
    }

    func testDailyFillsMissingDaysOldestFirst() {
        var s = TokenUsageStore()
        // 2026-07-15 Çarşamba. Dolu günler: 13 ve 15; 09..12 ve 14 boş.
        s.ingest(rec("1", "2026-07-13T10:00:00Z", counts: TokenCounts(input: 1_000_000)), calendar: utc)
        s.ingest(rec("2", "2026-07-15T08:00:00Z", counts: TokenCounts(output: 1_000_000)), calendar: utc)
        let now = UsageBucket.parseResetDate(from: "2026-07-15T12:00:00Z")!

        let series = TokenTrend.daily(from: s, days: 7, now: now, calendar: utc, pricing: TokenPricing())

        XCTAssertEqual(series.count, 7)
        XCTAssertEqual(series.first?.day, "2026-07-09")          // en eski başta
        XCTAssertEqual(series.last?.day, "2026-07-15")           // bugün sonda
        XCTAssertEqual(series.first?.counts.total, 0)            // boş gün sıfır
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
        XCTAssertEqual(today.counts.total, 1_000_500)    // token yine sayılır
        XCTAssertEqual(today.cost, 5.0, accuracy: 0.001) // fiyatsız model $'a katılmaz
        XCTAssertTrue(today.hasUnknownModel)
    }

    func testWeekComparisonUsesCalendarWeekBoundary() {
        var s = TokenUsageStore()
        // 2026-07-15 Çarşamba; hafta Pzt 13 – Paz 19. Önceki hafta Pzt 6 – Paz 12.
        s.ingest(rec("1", "2026-07-14T10:00:00Z", counts: TokenCounts(input: 1_000_000)), calendar: utc)  // bu hafta: $5
        s.ingest(rec("2", "2026-07-12T10:00:00Z", counts: TokenCounts(input: 2_000_000)), calendar: utc)  // geçen hafta (Pazar): $10
        s.ingest(rec("3", "2026-07-05T10:00:00Z", counts: TokenCounts(input: 8_000_000)), calendar: utc)  // 2 hafta önce: dahil değil
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
        s.ingest(rec("1", "2026-07-10T10:00:00Z", counts: TokenCounts(input: 1_000_000)), calendar: utc)  // Temmuz: $5
        let now = UsageBucket.parseResetDate(from: "2026-07-15T12:00:00Z")!

        let c = TokenTrend.monthComparison(from: s, now: now, calendar: utc, pricing: TokenPricing())
        XCTAssertEqual(c.currentCost, 5.0, accuracy: 0.001)
        XCTAssertEqual(c.previousCost, 0.0, accuracy: 0.001)  // Haziran boş
        XCTAssertNil(c.costDeltaRatio)                         // önceki 0 → "yeni"
    }
}
