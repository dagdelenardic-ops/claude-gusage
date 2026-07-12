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

    init(table: [String: ModelPrice] = TokenPricing.bundledTable) {
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

    func price(for modelID: String) -> ModelPrice? {
        table[Self.normalize(modelID)]
    }

    /// Notional USD for these counts under `modelID`, or nil if the model is unknown.
    func cost(of counts: TokenCounts, model modelID: String) -> Double? {
        guard let p = price(for: modelID) else { return nil }
        return Double(counts.input) * p.input
            + Double(counts.output) * p.output
            + Double(counts.cacheWrite) * p.cacheWrite
            + Double(counts.cacheRead) * p.cacheRead
    }
}

extension TokenPricing {
    /// List prices in USD per **million** tokens. Cache-write ≈ 1.25× input,
    /// cache-read ≈ 0.1× input (standard 5-minute cache multipliers).
    ///
    /// NOTE: verify these against current Anthropic pricing before each release.
    /// Fable is intentionally omitted (no public list price) → treated as an
    /// unknown model: its tokens still count, its cost shows "?".
    static let bundledTable: [String: ModelPrice] = [
        "opus":   perMillion(input: 15,   output: 75),
        "sonnet": perMillion(input: 3,    output: 15),
        "haiku":  perMillion(input: 0.80, output: 4),
    ]

    private static func perMillion(input: Double, output: Double) -> ModelPrice {
        ModelPrice(
            input: input / 1_000_000,
            output: output / 1_000_000,
            cacheWrite: (input * 1.25) / 1_000_000,
            cacheRead:  (input * 0.10) / 1_000_000
        )
    }
}
