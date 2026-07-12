import XCTest
@testable import ClaudeUsageBar

final class TokenPricingTests: XCTestCase {
    func testNormalizeMapsFamilies() {
        XCTAssertEqual(TokenPricing.normalize("claude-opus-4-8"), "opus")
        XCTAssertEqual(TokenPricing.normalize("claude-sonnet-5"), "sonnet")
        XCTAssertEqual(TokenPricing.normalize("claude-haiku-4-5-20251001"), "haiku")
        XCTAssertEqual(TokenPricing.normalize("claude-fable-5"), "fable")
    }

    func testNormalizeUnknownReturnsLowercased() {
        XCTAssertEqual(TokenPricing.normalize("Custom-Model-X"), "custom-model-x")
    }
}
