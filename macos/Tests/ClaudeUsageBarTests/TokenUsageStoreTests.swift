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

    func testRangeMembership() {
        let cal = utcCalendar
        let now = UsageBucket.parseResetDate(from: "2026-07-12T12:00:00Z")!
        XCTAssertTrue(UsageRange.today.contains(dayKey: "2026-07-12", now: now, calendar: cal))
        XCTAssertFalse(UsageRange.today.contains(dayKey: "2026-07-11", now: now, calendar: cal))
        XCTAssertTrue(UsageRange.month.contains(dayKey: "2026-07-01", now: now, calendar: cal))
        XCTAssertFalse(UsageRange.month.contains(dayKey: "2026-06-30", now: now, calendar: cal))
        XCTAssertTrue(UsageRange.all.contains(dayKey: "2020-01-01", now: now, calendar: cal))
    }
}
