import Foundation

/// Token counts for one or more assistant messages. All fields are raw token counts.
struct TokenCounts: Codable, Equatable {
    var input: Int = 0
    var output: Int = 0
    var cacheWrite: Int = 0   // cache_creation_input_tokens
    var cacheRead: Int = 0    // cache_read_input_tokens

    var total: Int { input + output + cacheWrite + cacheRead }

    static func + (lhs: TokenCounts, rhs: TokenCounts) -> TokenCounts {
        TokenCounts(
            input: lhs.input + rhs.input,
            output: lhs.output + rhs.output,
            cacheWrite: lhs.cacheWrite + rhs.cacheWrite,
            cacheRead: lhs.cacheRead + rhs.cacheRead
        )
    }
}

/// One deduplicated assistant message's token usage, parsed from a JSONL line.
struct UsageRecord: Equatable {
    let timestamp: Date
    let model: String
    let project: String    // the transcript's top-level `cwd`
    let counts: TokenCounts
    let dedupKey: String    // "\(message.id)|\(requestId)"
}
