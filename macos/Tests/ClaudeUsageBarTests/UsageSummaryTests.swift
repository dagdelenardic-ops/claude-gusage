import XCTest
@testable import ClaudeUsageBar

final class UsageSummaryTests: XCTestCase {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }

    private func store() -> TokenUsageStore {
        var s = TokenUsageStore()
        func rec(_ k: String, _ model: String, _ proj: String, _ counts: TokenCounts) -> UsageRecord {
            UsageRecord(timestamp: UsageBucket.parseResetDate(from: "2026-07-12T08:00:00Z")!,
                        model: model, project: proj, counts: counts, dedupKey: k)
        }
        s.ingest(rec("1", "claude-opus-4-8", "/A", TokenCounts(input: 1_000_000, output: 1_000_000)), calendar: utc)
        s.ingest(rec("2", "claude-sonnet-5", "/B", TokenCounts(input: 0, cacheRead: 1_000_000)), calendar: utc)
        s.ingest(rec("3", "claude-fable-5", "/A", TokenCounts(input: 500)), calendar: utc) // unknown price
        return s
    }

    func testSummaryTotalsAndUnknownFlag() {
        let now = UsageBucket.parseResetDate(from: "2026-07-12T12:00:00Z")!
        let sum = UsageSummary.compute(from: store(), range: .today, now: now,
                                       calendar: utc, pricing: TokenPricing())
        XCTAssertEqual(sum.counts.total, 1_000_000 + 1_000_000 + 1_000_000 + 500)
        XCTAssertTrue(sum.hasUnknownModel)          // fable priced nil
        // opus 90 + sonnet cacheRead 0.30; fable contributes nothing to cost
        XCTAssertEqual(sum.cost, 90.0 + 0.30, accuracy: 0.001)
    }

    func testSummaryBreakdownsSortedByCostThenTokens() {
        let now = UsageBucket.parseResetDate(from: "2026-07-12T12:00:00Z")!
        let sum = UsageSummary.compute(from: store(), range: .all, now: now,
                                       calendar: utc, pricing: TokenPricing())
        XCTAssertEqual(sum.byModel.first?.model, "opus")     // highest cost
        XCTAssertEqual(Set(sum.byProject.map(\.project)), ["/A", "/B"])
    }

    func testCacheReadRatio() {
        let now = UsageBucket.parseResetDate(from: "2026-07-12T12:00:00Z")!
        let sum = UsageSummary.compute(from: store(), range: .today, now: now,
                                       calendar: utc, pricing: TokenPricing())
        // input-side tokens: opus input 1M + sonnet cacheRead 1M + fable input 500
        // cacheRead / (input + cacheWrite + cacheRead)
        let expected = 1_000_000.0 / Double(1_000_000 + 1_000_000 + 500)
        XCTAssertEqual(sum.cacheReadRatio, expected, accuracy: 0.0001)
    }
}
