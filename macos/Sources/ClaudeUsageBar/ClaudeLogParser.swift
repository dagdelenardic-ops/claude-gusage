import Foundation

/// Parses Claude Code JSONL transcript bytes into usage records.
/// Pure and side-effect-free — the service handles all file I/O.
enum ClaudeLogParser {

    /// Minimal decodable view of a transcript line — only the fields we need.
    private struct RawLine: Decodable {
        let type: String?
        let timestamp: String?
        let cwd: String?
        let requestId: String?
        let message: RawMessage?

        struct RawMessage: Decodable {
            let id: String?
            let model: String?
            let usage: RawUsage?
        }
        struct RawUsage: Decodable {
            let inputTokens: Int?
            let outputTokens: Int?
            let cacheCreationInputTokens: Int?
            let cacheReadInputTokens: Int?
            enum CodingKeys: String, CodingKey {
                case inputTokens = "input_tokens"
                case outputTokens = "output_tokens"
                case cacheCreationInputTokens = "cache_creation_input_tokens"
                case cacheReadInputTokens = "cache_read_input_tokens"
            }
        }
    }

    /// Parse newline-delimited JSON. Skips non-assistant lines, lines without
    /// usage or a parseable timestamp, and any malformed line.
    static func parseLines(_ data: Data) -> [UsageRecord] {
        guard !data.isEmpty else { return [] }
        let decoder = JSONDecoder()
        let newline = UInt8(ascii: "\n")
        let cr = UInt8(ascii: "\r")

        return data.split(separator: newline, omittingEmptySubsequences: true).compactMap { slice in
            var lineData = Data(slice)
            if lineData.last == cr { lineData.removeLast() }  // tolerate CRLF
            guard
                let raw = try? decoder.decode(RawLine.self, from: lineData),
                raw.type == "assistant",
                let message = raw.message,
                let messageID = message.id,
                let model = message.model,
                let usage = message.usage,
                let timestamp = UsageBucket.parseResetDate(from: raw.timestamp)
            else { return nil }

            let counts = TokenCounts(
                input: usage.inputTokens ?? 0,
                output: usage.outputTokens ?? 0,
                cacheWrite: usage.cacheCreationInputTokens ?? 0,
                cacheRead: usage.cacheReadInputTokens ?? 0
            )
            guard counts.total > 0 else { return nil }

            return UsageRecord(
                timestamp: timestamp,
                model: model,
                project: raw.cwd ?? "unknown",
                counts: counts,
                dedupKey: "\(messageID)|\(raw.requestId ?? "")"
            )
        }
    }
}
