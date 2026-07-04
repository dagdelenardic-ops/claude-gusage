import XCTest
@testable import ClaudeUsageBar

final class FablePromoTests: XCTestCase {
    private func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)!
    }

    func testActiveWellWithinWindow() {
        // Comfortably inside the window in any time zone.
        XCTAssertTrue(FablePromo.isActive(now: date("2026-07-04T12:00:00Z")))
    }

    func testActiveJustBeforeEnd() {
        XCTAssertTrue(FablePromo.isActive(now: FablePromo.endDate.addingTimeInterval(-1)))
    }

    func testInactiveAtEnd() {
        XCTAssertFalse(FablePromo.isActive(now: FablePromo.endDate))
    }

    func testInactiveAfterEnd() {
        XCTAssertFalse(FablePromo.isActive(now: FablePromo.endDate.addingTimeInterval(3600)))
    }
}
