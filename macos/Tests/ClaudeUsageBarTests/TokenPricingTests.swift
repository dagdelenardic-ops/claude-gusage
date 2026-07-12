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

    func testCostForKnownModel() {
        // opus: $15/MTok input, $75/MTok output → per-token 15e-6, 75e-6
        let pricing = TokenPricing()
        let counts = TokenCounts(input: 1_000_000, output: 1_000_000, cacheWrite: 0, cacheRead: 0)
        let cost = pricing.cost(of: counts, model: "claude-opus-4-8")
        XCTAssertNotNil(cost)
        XCTAssertEqual(cost!, 90.0, accuracy: 0.0001) // 15 + 75
    }

    func testCostCacheMultipliers() {
        let pricing = TokenPricing()
        // sonnet input $3/MTok → cacheWrite 1.25×=3.75, cacheRead 0.1×=0.30 per MTok
        let counts = TokenCounts(input: 0, output: 0, cacheWrite: 1_000_000, cacheRead: 1_000_000)
        let cost = pricing.cost(of: counts, model: "claude-sonnet-5")!
        XCTAssertEqual(cost, 3.75 + 0.30, accuracy: 0.0001)
    }

    func testCostUnknownModelIsNil() {
        let pricing = TokenPricing()
        XCTAssertNil(pricing.cost(of: TokenCounts(input: 100), model: "gpt-4"))
    }
}
