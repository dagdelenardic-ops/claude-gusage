import XCTest
@testable import ClaudeUsageBar

final class TokenFormatTests: XCTestCase {
    func testCompact() {
        XCTAssertEqual(TokenFormat.compact(900), "900")
        XCTAssertEqual(TokenFormat.compact(45_000), "45.0K")
        XCTAssertEqual(TokenFormat.compact(12_300_000), "12.3M")
    }
}
