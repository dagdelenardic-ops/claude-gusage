import XCTest
@testable import ClaudeUsageBar

final class TokenUsageStoreTests: XCTestCase {
    private var utcCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private func record(_ key: String, model: String = "claude-opus-4-8",
                        project: String = "/P", input: Int = 10,
                        ts: String = "2026-07-12T08:00:00Z") -> UsageRecord {
        UsageRecord(timestamp: UsageBucket.parseResetDate(from: ts)!,
                    model: model, project: project,
                    counts: TokenCounts(input: input), dedupKey: key)
    }

    func testIngestBucketsByDayModelProject() {
        var store = TokenUsageStore()
        store.ingest(record("a"), calendar: utcCalendar)
        store.ingest(record("b", input: 5), calendar: utcCalendar)
        let day = store.buckets["2026-07-12"]!
        XCTAssertEqual(day["opus"]!["/P"]!, TokenCounts(input: 15))
    }

    func testIngestIsIdempotentOnDedupKey() {
        var store = TokenUsageStore()
        store.ingest(record("dup"), calendar: utcCalendar)
        store.ingest(record("dup", input: 999), calendar: utcCalendar) // same key → ignored
        XCTAssertEqual(store.buckets["2026-07-12"]!["opus"]!["/P"]!, TokenCounts(input: 10))
        XCTAssertEqual(store.seenKeys.count, 1)
    }
}
