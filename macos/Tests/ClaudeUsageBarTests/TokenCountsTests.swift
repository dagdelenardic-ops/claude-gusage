import XCTest
@testable import ClaudeUsageBar

final class TokenCountsTests: XCTestCase {
    func testTotalSumsAllFour() {
        let c = TokenCounts(input: 10, output: 20, cacheWrite: 5, cacheRead: 100)
        XCTAssertEqual(c.total, 135)
    }

    func testAdditionIsFieldwise() {
        let a = TokenCounts(input: 1, output: 2, cacheWrite: 3, cacheRead: 4)
        let b = TokenCounts(input: 10, output: 20, cacheWrite: 30, cacheRead: 40)
        XCTAssertEqual(a + b, TokenCounts(input: 11, output: 22, cacheWrite: 33, cacheRead: 44))
    }
}
