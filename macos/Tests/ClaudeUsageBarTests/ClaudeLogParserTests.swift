import XCTest
@testable import ClaudeUsageBar

final class ClaudeLogParserTests: XCTestCase {
    private func line(_ json: String) -> Data { Data((json + "\n").utf8) }

    func testParsesAssistantUsageLine() {
        let json = """
        {"type":"assistant","timestamp":"2026-07-12T08:55:00.000Z","cwd":"/Users/x/Proj","requestId":"req1","message":{"id":"msg1","model":"claude-opus-4-8","usage":{"input_tokens":10,"output_tokens":20,"cache_creation_input_tokens":5,"cache_read_input_tokens":100}}}
        """
        let records = ClaudeLogParser.parseLines(line(json))
        XCTAssertEqual(records.count, 1)
        let r = records[0]
        XCTAssertEqual(r.model, "claude-opus-4-8")
        XCTAssertEqual(r.project, "/Users/x/Proj")
        XCTAssertEqual(r.dedupKey, "msg1|req1")
        XCTAssertEqual(r.counts, TokenCounts(input: 10, output: 20, cacheWrite: 5, cacheRead: 100))
    }
}
