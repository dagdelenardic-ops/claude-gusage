import Foundation

/// Per-token USD prices for one model family.
struct ModelPrice: Codable, Equatable {
    let input: Double
    let output: Double
    let cacheWrite: Double
    let cacheRead: Double
}

/// Maps model ids to prices and computes notional cost.
struct TokenPricing {
    private let table: [String: ModelPrice]

    init(table: [String: ModelPrice] = [:]) {
        self.table = table
    }

    /// Collapse a raw model id to a family key. Order matters only in that each
    /// id is expected to contain exactly one family token.
    static func normalize(_ modelID: String) -> String {
        let lower = modelID.lowercased()
        for family in ["opus", "sonnet", "haiku", "fable"] where lower.contains(family) {
            return family
        }
        return lower
    }
}
