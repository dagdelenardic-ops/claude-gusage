import XCTest
@testable import ClaudeUsageBar

final class UsageRecordTests: XCTestCase {
    func testRecordStoresFields() {
        let r = UsageRecord(
            timestamp: Date(timeIntervalSince1970: 0),
            model: "claude-opus-4-8",
            project: "/Users/x/Proj",
            counts: TokenCounts(input: 5),
            dedupKey: "msg1|req1"
        )
        XCTAssertEqual(r.model, "claude-opus-4-8")
        XCTAssertEqual(r.dedupKey, "msg1|req1")
        XCTAssertEqual(r.counts.total, 5)
    }
}
