# Lokal Token & Maliyet Paneli — Implementation Plan

> **For the implementer:** Use the `subagent-driven-development` skill to implement this plan task-by-task. Each task is a full TDD cycle (write failing test → verify fail → implement → verify pass → commit).

**Goal:** Add an expandable "Token & Maliyet" section to the popover that mines `~/.claude/projects/*.jsonl` and shows real token usage, notional USD cost, per-model and per-project attribution, and cache efficiency.

**Architecture:** A self-contained subsystem of five new files. Pure value types (`TokenCounts`, `TokenPricing`, `UsageRecord`, `TokenUsageStore`, `UsageSummary`) hold all logic and are fully unit-tested. `ClaudeLogParser` turns JSONL bytes into records. `TokenUsageService` (`@MainActor ObservableObject`) does incremental file I/O, persists an aggregate store, and publishes summaries. `TokenUsageView` renders. The existing `UsageService`/OAuth code is **not touched**; only `PopoverView`, `SettingsView`, and `ClaudeUsageBarApp` get small wiring changes.

**Tech Stack:** Swift 5.9, SwiftPM, SwiftUI/AppKit, XCTest. macOS 14+.

**Spec:** `docs/superpowers/specs/2026-07-12-lokal-token-maliyet-paneli-design.md`

**Conventions (verified against the codebase):**
- Tests: `cd macos && swift test`; build: `cd macos && swift build`.
- Test files live in `macos/Tests/ClaudeUsageBarTests/`, use `import XCTest` + `@testable import ClaudeUsageBar`, `final class XTests: XCTestCase`.
- Source files live in `macos/Sources/ClaudeUsageBar/`, one purpose per file.
- Reuse `ExtraUsage.formatUSD(_:)` for dollars and `UsageBucket.parseResetDate(from:)` for ISO timestamps (both already exist in `UsageModel.swift`).
- Persistence dir: `~/.config/claude-usage-bar/` (same as `UsageHistoryService`).
- Colors: `Theme.accent`, `Theme.usageColor(_:)`, `Theme.neutral`.

**Commit convention:** `feat:` / `test:` / `refactor:` prefixes, trailing `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`. Work directly on `main` (matches this fork's workflow). Do not push unless asked.

---

## Group A — Pricing & token counts (pure, no I/O)

### Task 1: `TokenCounts` value type

**Objective:** A summable bag of the four token kinds.

**Files:**
- Create: `macos/Sources/ClaudeUsageBar/TokenUsageModel.swift`
- Test: `macos/Tests/ClaudeUsageBarTests/TokenCountsTests.swift`

**Step 1 — Failing test** (`TokenCountsTests.swift`):
```swift
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
```

**Step 2 — Verify fail:** `cd macos && swift test --filter TokenCountsTests`
Expected: FAIL — `TokenCounts` not found.

**Step 3 — Implement** (start `TokenUsageModel.swift`):
```swift
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
```

**Step 4 — Verify pass:** `cd macos && swift test --filter TokenCountsTests` → PASS.

**Step 5 — Commit:**
```bash
git add macos/Sources/ClaudeUsageBar/TokenUsageModel.swift macos/Tests/ClaudeUsageBarTests/TokenCountsTests.swift
git commit -m "feat: add TokenCounts value type"
```

---

### Task 2: Model id normalization

**Objective:** Collapse raw model ids (`claude-opus-4-8`) to family keys (`opus`).

**Files:**
- Create: `macos/Sources/ClaudeUsageBar/TokenPricing.swift`
- Test: `macos/Tests/ClaudeUsageBarTests/TokenPricingTests.swift`

**Step 1 — Failing test:**
```swift
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
```

**Step 2 — Verify fail:** `cd macos && swift test --filter TokenPricingTests` → FAIL.

**Step 3 — Implement** (start `TokenPricing.swift`):
```swift
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
}
```

**Step 4 — Verify pass.**

**Step 5 — Commit:**
```bash
git add macos/Sources/ClaudeUsageBar/TokenPricing.swift macos/Tests/ClaudeUsageBarTests/TokenPricingTests.swift
git commit -m "feat: add model id normalization"
```

---

### Task 3: Bundled price table + cost calculation

**Objective:** Compute notional USD from `TokenCounts` + model; return `nil` for unknown models.

**Files:**
- Modify: `macos/Sources/ClaudeUsageBar/TokenPricing.swift`
- Modify: `macos/Tests/ClaudeUsageBarTests/TokenPricingTests.swift`

**Step 1 — Failing tests** (append):
```swift
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
```

**Step 2 — Verify fail.**

**Step 3 — Implement** (append to `TokenPricing.swift`, inside `struct TokenPricing`):
```swift
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
```

And append after the struct:
```swift
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
```

**Step 4 — Verify pass.**

**Step 5 — Commit:**
```bash
git add macos/Sources/ClaudeUsageBar/TokenPricing.swift macos/Tests/ClaudeUsageBarTests/TokenPricingTests.swift
git commit -m "feat: add bundled price table and cost calculation"
```

---

## Group B — Parsing (pure)

### Task 4: `UsageRecord` model

**Objective:** One deduplicated assistant message's usage.

**Files:**
- Modify: `macos/Sources/ClaudeUsageBar/TokenUsageModel.swift`
- Test: `macos/Tests/ClaudeUsageBarTests/TokenCountsTests.swift` (add a case) — or new file `UsageRecordTests.swift`.

**Step 1 — Failing test** (new file `UsageRecordTests.swift`):
```swift
import XCTest
@testable import ClaudeUsageBar

final class UsageRecordTests: XCTestCase {
    func testRecordStoresFields() {
        let r = UsageRecord(
            timestamp: Date(timeIntervalSince1970: 0),
            model: "claude-opus-4-8",
            project: "/Users/x/Proj",
            counts: TokenCounts(input: 5),
            dedupKey: "msg1|req1"
        )
        XCTAssertEqual(r.model, "claude-opus-4-8")
        XCTAssertEqual(r.dedupKey, "msg1|req1")
        XCTAssertEqual(r.counts.total, 5)
    }
}
```

**Step 2 — Verify fail.**

**Step 3 — Implement** (append to `TokenUsageModel.swift`):
```swift
/// One deduplicated assistant message's token usage, parsed from a JSONL line.
struct UsageRecord: Equatable {
    let timestamp: Date
    let model: String
    let project: String    // the transcript's top-level `cwd`
    let counts: TokenCounts
    let dedupKey: String    // "\(message.id)|\(requestId)"
}
```

**Step 4 — Verify pass.**

**Step 5 — Commit:**
```bash
git add macos/Sources/ClaudeUsageBar/TokenUsageModel.swift macos/Tests/ClaudeUsageBarTests/UsageRecordTests.swift
git commit -m "feat: add UsageRecord model"
```

---

### Task 5: JSONL line parser — happy path

**Objective:** Turn assistant JSONL lines into `UsageRecord`s.

**Files:**
- Create: `macos/Sources/ClaudeUsageBar/ClaudeLogParser.swift`
- Test: `macos/Tests/ClaudeUsageBarTests/ClaudeLogParserTests.swift`

**Step 1 — Failing test:**
```swift
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
```

**Step 2 — Verify fail.**

**Step 3 — Implement** (`ClaudeLogParser.swift`):
```swift
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
                let model = message.id != nil ? message.model : nil, // require id + model
                let messageID = message.id,
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
```

**Step 4 — Verify pass.**

**Step 5 — Commit:**
```bash
git add macos/Sources/ClaudeUsageBar/ClaudeLogParser.swift macos/Tests/ClaudeUsageBarTests/ClaudeLogParserTests.swift
git commit -m "feat: add JSONL usage parser (happy path)"
```

---

### Task 6: Parser skips noise

**Objective:** Prove non-assistant, no-usage, zero-token, missing-timestamp, and malformed lines are skipped.

**Files:**
- Modify: `macos/Tests/ClaudeUsageBarTests/ClaudeLogParserTests.swift`

**Step 1 — Failing tests** (append):
```swift
    func testSkipsUserAndMalformedAndEmptyLines() {
        let userLine = #"{"type":"user","message":{"role":"user","content":"hi"}}"#
        let noUsage = #"{"type":"assistant","timestamp":"2026-07-12T08:55:00Z","message":{"id":"m","model":"claude-opus-4-8"}}"#
        let zeroTokens = #"{"type":"assistant","timestamp":"2026-07-12T08:55:00Z","requestId":"r","message":{"id":"m2","model":"claude-opus-4-8","usage":{"input_tokens":0,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}"#
        let noTimestamp = #"{"type":"assistant","message":{"id":"m3","model":"claude-opus-4-8","usage":{"input_tokens":5}}}"#
        let garbage = "not json at all"
        let good = #"{"type":"assistant","timestamp":"2026-07-12T08:55:00Z","requestId":"r2","message":{"id":"m4","model":"claude-sonnet-5","usage":{"input_tokens":7}}}"#

        let blob = ([userLine, noUsage, zeroTokens, noTimestamp, garbage, good]).joined(separator: "\n")
        let records = ClaudeLogParser.parseLines(Data(blob.utf8))
        XCTAssertEqual(records.map(\.dedupKey), ["m4|r2"])
    }
```

**Step 2 — Verify fail** (if any slip through, tighten the guards in Task 5's implementation).

**Step 3 — Implement:** No new code expected — Task 5 guards already cover these. If a case fails, fix `parseLines`.

**Step 4 — Verify pass.**

**Step 5 — Commit:**
```bash
git add macos/Tests/ClaudeUsageBarTests/ClaudeLogParserTests.swift
git commit -m "test: parser skips non-usage and malformed lines"
```

---

## Group C — Aggregation (pure)

### Task 7: `TokenUsageStore` — dedup + day/model/project buckets

**Objective:** Ingest records into `[dayKey: [model: [project: TokenCounts]]]`, deduped by key.

**Files:**
- Create: `macos/Sources/ClaudeUsageBar/TokenUsageStore.swift`
- Test: `macos/Tests/ClaudeUsageBarTests/TokenUsageStoreTests.swift`

**Step 1 — Failing test:**
```swift
import XCTest
@testable import ClaudeUsageBar

final class TokenUsageStoreTests: XCTestCase {
    private var utcCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private func record(_ key: String, model: String = "claude-opus-4-8",
                        project: String = "/P", input: Int = 10,
                        ts: String = "2026-07-12T08:00:00Z") -> UsageRecord {
        UsageRecord(timestamp: UsageBucket.parseResetDate(from: ts)!,
                    model: model, project: project,
                    counts: TokenCounts(input: input), dedupKey: key)
    }

    func testIngestBucketsByDayModelProject() {
        var store = TokenUsageStore()
        store.ingest(record("a"), calendar: utcCalendar)
        store.ingest(record("b", input: 5), calendar: utcCalendar)
        let day = store.buckets["2026-07-12"]!
        XCTAssertEqual(day["opus"]!["/P"]!, TokenCounts(input: 15))
    }

    func testIngestIsIdempotentOnDedupKey() {
        var store = TokenUsageStore()
        store.ingest(record("dup"), calendar: utcCalendar)
        store.ingest(record("dup", input: 999), calendar: utcCalendar) // same key → ignored
        XCTAssertEqual(store.buckets["2026-07-12"]!["opus"]!["/P"]!, TokenCounts(input: 10))
        XCTAssertEqual(store.seenKeys.count, 1)
    }
}
```

Note: buckets key by **family** (`opus`) via `TokenPricing.normalize`, so cost lookups and UI grouping align.

**Step 2 — Verify fail.**

**Step 3 — Implement** (`TokenUsageStore.swift`):
```swift
import Foundation

struct FileCursor: Codable, Equatable {
    var offset: Int    // bytes already consumed
    var mtime: Date    // file modification date when consumed
}

/// Persisted, incrementally-updated aggregate of local token usage.
struct TokenUsageStore: Codable, Equatable {
    /// absolute file path -> read cursor
    var cursors: [String: FileCursor] = [:]
    /// dedup keys already counted ("message.id|requestId")
    var seenKeys: Set<String> = []
    /// "yyyy-MM-dd" (local day) -> family model key -> project(cwd) -> counts
    var buckets: [String: [String: [String: TokenCounts]]] = [:]

    /// Add a record unless its dedup key was already counted.
    mutating func ingest(_ record: UsageRecord, calendar: Calendar = .current) {
        guard seenKeys.insert(record.dedupKey).inserted else { return }
        let day = Self.dayKey(record.timestamp, calendar: calendar)
        let model = TokenPricing.normalize(record.model)
        let existing = buckets[day]?[model]?[record.project] ?? TokenCounts()
        buckets[day, default: [:]][model, default: [:]][record.project] = existing + record.counts
    }

    /// Local "yyyy-MM-dd" for bucketing.
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
```

**Step 4 — Verify pass.**

**Step 5 — Commit:**
```bash
git add macos/Sources/ClaudeUsageBar/TokenUsageStore.swift macos/Tests/ClaudeUsageBarTests/TokenUsageStoreTests.swift
git commit -m "feat: add TokenUsageStore with dedup and day/model/project buckets"
```

---

### Task 8: `UsageRange` + day membership

**Objective:** Define Today / This month / All-time and decide which day-keys belong.

**Files:**
- Modify: `macos/Sources/ClaudeUsageBar/TokenUsageStore.swift`
- Test: `macos/Tests/ClaudeUsageBarTests/TokenUsageStoreTests.swift`

**Step 1 — Failing tests** (append):
```swift
    func testRangeMembership() {
        let cal = utcCalendar
        let now = UsageBucket.parseResetDate(from: "2026-07-12T12:00:00Z")!
        XCTAssertTrue(UsageRange.today.contains(dayKey: "2026-07-12", now: now, calendar: cal))
        XCTAssertFalse(UsageRange.today.contains(dayKey: "2026-07-11", now: now, calendar: cal))
        XCTAssertTrue(UsageRange.month.contains(dayKey: "2026-07-01", now: now, calendar: cal))
        XCTAssertFalse(UsageRange.month.contains(dayKey: "2026-06-30", now: now, calendar: cal))
        XCTAssertTrue(UsageRange.all.contains(dayKey: "2020-01-01", now: now, calendar: cal))
    }
```

**Step 2 — Verify fail.**

**Step 3 — Implement** (append to `TokenUsageStore.swift`):
```swift
enum UsageRange: String, CaseIterable, Identifiable {
    case today, month, all
    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: return "Bugün"
        case .month: return "Bu ay"
        case .all:   return "Tüm zamanlar"
        }
    }

    /// True when a "yyyy-MM-dd" day-key falls inside this range relative to `now`.
    func contains(dayKey: String, now: Date, calendar: Calendar = .current) -> Bool {
        switch self {
        case .all:
            return true
        case .today:
            return dayKey == TokenUsageStore.dayKey(now, calendar: calendar)
        case .month:
            let c = calendar.dateComponents([.year, .month], from: now)
            return dayKey.hasPrefix(String(format: "%04d-%02d-", c.year ?? 0, c.month ?? 0))
        }
    }
}
```

**Step 4 — Verify pass.**

**Step 5 — Commit:**
```bash
git add macos/Sources/ClaudeUsageBar/TokenUsageStore.swift macos/Tests/ClaudeUsageBarTests/TokenUsageStoreTests.swift
git commit -m "feat: add UsageRange with day membership"
```

---

### Task 9: `UsageSummary` — totals, breakdowns, cache stats

**Objective:** Reduce the store to a display-ready summary for a range, using pricing.

**Files:**
- Create: `macos/Sources/ClaudeUsageBar/UsageSummary.swift`
- Test: `macos/Tests/ClaudeUsageBarTests/UsageSummaryTests.swift`

**Step 1 — Failing test:**
```swift
import XCTest
@testable import ClaudeUsageBar

final class UsageSummaryTests: XCTestCase {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }

    private func store() -> TokenUsageStore {
        var s = TokenUsageStore()
        func rec(_ k: String, _ model: String, _ proj: String, _ counts: TokenCounts) -> UsageRecord {
            UsageRecord(timestamp: UsageBucket.parseResetDate(from: "2026-07-12T08:00:00Z")!,
                        model: model, project: proj, counts: counts, dedupKey: k)
        }
        s.ingest(rec("1", "claude-opus-4-8", "/A", TokenCounts(input: 1_000_000, output: 1_000_000)), calendar: utc)
        s.ingest(rec("2", "claude-sonnet-5", "/B", TokenCounts(input: 0, cacheRead: 1_000_000)), calendar: utc)
        s.ingest(rec("3", "claude-fable-5", "/A", TokenCounts(input: 500)), calendar: utc) // unknown price
        return s
    }

    func testSummaryTotalsAndUnknownFlag() {
        let now = UsageBucket.parseResetDate(from: "2026-07-12T12:00:00Z")!
        let sum = UsageSummary.compute(from: store(), range: .today, now: now,
                                       calendar: utc, pricing: TokenPricing())
        XCTAssertEqual(sum.counts.total, 1_000_000 + 1_000_000 + 1_000_000 + 500)
        XCTAssertTrue(sum.hasUnknownModel)          // fable priced nil
        // opus 90 + sonnet cacheRead 0.30; fable contributes nothing to cost
        XCTAssertEqual(sum.cost, 90.0 + 0.30, accuracy: 0.001)
    }

    func testSummaryBreakdownsSortedByCostThenTokens() {
        let now = UsageBucket.parseResetDate(from: "2026-07-12T12:00:00Z")!
        let sum = UsageSummary.compute(from: store(), range: .all, now: now,
                                       calendar: utc, pricing: TokenPricing())
        XCTAssertEqual(sum.byModel.first?.model, "opus")     // highest cost
        XCTAssertEqual(Set(sum.byProject.map(\.project)), ["/A", "/B"])
    }

    func testCacheReadRatio() {
        let now = UsageBucket.parseResetDate(from: "2026-07-12T12:00:00Z")!
        let sum = UsageSummary.compute(from: store(), range: .today, now: now,
                                       calendar: utc, pricing: TokenPricing())
        // input-side tokens: opus input 1M + sonnet cacheRead 1M + fable input 500
        // cacheRead / (input + cacheWrite + cacheRead)
        let expected = 1_000_000.0 / Double(1_000_000 + 1_000_000 + 500)
        XCTAssertEqual(sum.cacheReadRatio, expected, accuracy: 0.0001)
    }
}
```

**Step 2 — Verify fail.**

**Step 3 — Implement** (`UsageSummary.swift`):
```swift
import Foundation

struct ModelUsage: Identifiable, Equatable {
    let model: String            // family key, e.g. "opus"
    let counts: TokenCounts
    let cost: Double?            // nil = unknown price
    var id: String { model }
}

struct ProjectUsage: Identifiable, Equatable {
    let project: String          // full cwd path
    let counts: TokenCounts
    let cost: Double?
    var id: String { project }
    /// Last path component for compact display, falling back to the full path.
    var displayName: String {
        (project as NSString).lastPathComponent.isEmpty ? project : (project as NSString).lastPathComponent
    }
}

/// Display-ready reduction of a `TokenUsageStore` for one range.
struct UsageSummary: Equatable {
    let counts: TokenCounts
    let cost: Double
    let hasUnknownModel: Bool
    let byModel: [ModelUsage]      // sorted desc
    let byProject: [ProjectUsage]  // sorted desc
    /// cacheRead / (input + cacheWrite + cacheRead); 0 when no input-side tokens.
    let cacheReadRatio: Double
    /// Notional USD saved by cache reads vs. paying full input price.
    let cacheSavings: Double

    static func compute(
        from store: TokenUsageStore,
        range: UsageRange,
        now: Date,
        calendar: Calendar = .current,
        pricing: TokenPricing
    ) -> UsageSummary {
        var modelCounts: [String: TokenCounts] = [:]
        var projectCounts: [String: TokenCounts] = [:]
        var total = TokenCounts()

        for (day, models) in store.buckets where range.contains(dayKey: day, now: now, calendar: calendar) {
            for (model, projects) in models {
                for (project, counts) in projects {
                    modelCounts[model, default: TokenCounts()] = modelCounts[model, default: TokenCounts()] + counts
                    projectCounts[project, default: TokenCounts()] = projectCounts[project, default: TokenCounts()] + counts
                    total = total + counts
                }
            }
        }

        var cost = 0.0
        var hasUnknown = false
        var savings = 0.0

        let byModel: [ModelUsage] = modelCounts.map { model, counts in
            let c = pricing.cost(of: counts, model: model)
            if let c { cost += c } else { hasUnknown = true }
            if let p = pricing.price(for: model) {
                savings += Double(counts.cacheRead) * (p.input - p.cacheRead)
            }
            return ModelUsage(model: model, counts: counts, cost: c)
        }.sorted { lhs, rhs in
            ((lhs.cost ?? -1), lhs.counts.total) > ((rhs.cost ?? -1), rhs.counts.total)
        }

        let byProject: [ProjectUsage] = projectCounts.map { project, counts in
            // A project spans models; approximate its cost by summing each model's rate.
            // Cheap path: leave project cost nil unless all its tokens map to known models.
            return ProjectUsage(project: project, counts: counts, cost: nil)
        }.sorted { $0.counts.total > $1.counts.total }

        let inputSide = total.input + total.cacheWrite + total.cacheRead
        let ratio = inputSide > 0 ? Double(total.cacheRead) / Double(inputSide) : 0

        return UsageSummary(
            counts: total, cost: cost, hasUnknownModel: hasUnknown,
            byModel: byModel, byProject: byProject,
            cacheReadRatio: ratio, cacheSavings: savings
        )
    }
}
```

> **Note on project cost:** buckets are keyed by `(day, model, project)`, so a per-project cost *is* computable by summing each `(model, project)` cell with that model's price. Task 9 keeps `ProjectUsage.cost = nil` (tokens-only) to stay bite-sized; **Task 9b** (optional, below) upgrades it. Ship tokens-only first if time-boxed.

**Step 4 — Verify pass.**

**Step 5 — Commit:**
```bash
git add macos/Sources/ClaudeUsageBar/UsageSummary.swift macos/Tests/ClaudeUsageBarTests/UsageSummaryTests.swift
git commit -m "feat: add UsageSummary reduction with model breakdown and cache stats"
```

---

### Task 9b (optional): per-project cost

**Objective:** Fill `ProjectUsage.cost` by summing each model's contribution within the project.

**Files:** Modify `UsageSummary.swift` + add a test asserting `/A`'s cost equals opus(90) + fable(nil→skip) and flags unknown at project level. Implement by aggregating `projectModelCounts: [String: [String: TokenCounts]]` alongside the existing loops. Only do this if the tokens-only project view feels insufficient during review.

---

## Group D — Service (I/O + ObservableObject)

### Task 10: Incremental appended-bytes reader

**Objective:** Read only new bytes since the last cursor; handle truncation and partial trailing lines.

**Files:**
- Create: `macos/Sources/ClaudeUsageBar/TokenUsageService.swift`
- Test: `macos/Tests/ClaudeUsageBarTests/TokenUsageReaderTests.swift`

**Step 1 — Failing test** (writes to a temp file):
```swift
import XCTest
@testable import ClaudeUsageBar

final class TokenUsageReaderTests: XCTestCase {
    private func tempFile() -> String {
        let dir = NSTemporaryDirectory()
        return (dir as NSString).appendingPathComponent("tur-\(UUID().uuidString).jsonl")
    }

    func testReadsOnlyCompleteAppendedLines() throws {
        let path = tempFile()
        defer { try? FileManager.default.removeItem(atPath: path) }

        try "line1\nline2\n".write(toFile: path, atomically: true, encoding: .utf8)
        let first = TokenUsageReader.readAppended(path: path, cursor: nil)
        XCTAssertEqual(String(decoding: first!.data, as: UTF8.self), "line1\nline2\n")

        // Append a complete line plus a partial one; only the complete part is consumed.
        let handle = FileHandle(forWritingAtPath: path)!
        handle.seekToEndOfFile()
        handle.write(Data("line3\npartial".utf8))
        try handle.close()

        let second = TokenUsageReader.readAppended(path: path, cursor: first!.cursor)
        XCTAssertEqual(String(decoding: second!.data, as: UTF8.self), "line3\n")
    }

    func testTruncationResetsToZero() throws {
        let path = tempFile()
        defer { try? FileManager.default.removeItem(atPath: path) }
        try "aaaa\nbbbb\n".write(toFile: path, atomically: true, encoding: .utf8)
        let first = TokenUsageReader.readAppended(path: path, cursor: nil)!
        try "x\n".write(toFile: path, atomically: true, encoding: .utf8) // smaller than cursor.offset
        let second = TokenUsageReader.readAppended(path: path, cursor: first.cursor)!
        XCTAssertEqual(String(decoding: second.data, as: UTF8.self), "x\n")
    }
}
```

**Step 2 — Verify fail.**

**Step 3 — Implement** (start `TokenUsageService.swift` with a nonisolated reader enum so it's testable off the main actor):
```swift
import Foundation
import Combine
import AppKit

/// Pure file-reading helper: returns newly-appended, newline-complete bytes.
enum TokenUsageReader {
    static func readAppended(
        path: String,
        cursor: FileCursor?,
        fileManager: FileManager = .default
    ) -> (data: Data, cursor: FileCursor)? {
        guard
            let attrs = try? fileManager.attributesOfItem(atPath: path),
            let size = (attrs[.size] as? NSNumber)?.intValue,
            let mtime = attrs[.modificationDate] as? Date
        else { return nil }

        var start = cursor?.offset ?? 0
        if start > size { start = 0 }                 // truncated / rotated
        if start == size { return (Data(), FileCursor(offset: size, mtime: mtime)) }

        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        try? handle.seek(toOffset: UInt64(start))
        let chunk = (try? handle.readToEnd()) ?? Data()

        // Consume only up to the last newline; leave a partial trailing line for next time.
        guard let lastNL = chunk.lastIndex(of: UInt8(ascii: "\n")) else {
            return (Data(), cursor ?? FileCursor(offset: start, mtime: mtime))
        }
        let end = chunk.index(after: lastNL)
        let consumed = chunk[chunk.startIndex..<end]
        return (Data(consumed), FileCursor(offset: start + consumed.count, mtime: mtime))
    }
}
```

**Step 4 — Verify pass.**

**Step 5 — Commit:**
```bash
git add macos/Sources/ClaudeUsageBar/TokenUsageService.swift macos/Tests/ClaudeUsageBarTests/TokenUsageReaderTests.swift
git commit -m "feat: add incremental appended-bytes reader"
```

---

### Task 11: `TokenUsageService` — persistence + refresh + published summaries

**Objective:** Enumerate `~/.claude/projects`, incrementally parse, ingest, persist the store, and publish summaries. `@MainActor ObservableObject`.

**Files:**
- Modify: `macos/Sources/ClaudeUsageBar/TokenUsageService.swift`
- Test: `macos/Tests/ClaudeUsageBarTests/TokenUsageServiceTests.swift`

**Step 1 — Failing test** (inject a temp projects dir + temp store path):
```swift
import XCTest
@testable import ClaudeUsageBar

@MainActor
final class TokenUsageServiceTests: XCTestCase {
    private func makeDirs() -> (projects: URL, storeFile: URL) {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tus-\(UUID().uuidString)")
        let projects = base.appendingPathComponent("projects")
        try? FileManager.default.createDirectory(at: projects.appendingPathComponent("Proj"),
                                                 withIntermediateDirectories: true)
        return (projects, base.appendingPathComponent("token-usage.json"))
    }

    func testRefreshParsesAndSummarizes() async throws {
        let (projects, storeFile) = makeDirs()
        let jsonl = projects.appendingPathComponent("Proj/session.jsonl")
        let line = #"{"type":"assistant","timestamp":"2026-07-12T08:00:00Z","cwd":"/Users/x/Proj","requestId":"r","message":{"id":"m","model":"claude-opus-4-8","usage":{"input_tokens":1000000,"output_tokens":1000000}}}"#
        try (line + "\n").write(to: jsonl, atomically: true, encoding: .utf8)

        let svc = TokenUsageService(projectsDir: projects, storeFileURL: storeFile)
        await svc.refresh()

        XCTAssertNotNil(svc.hasData)
        let sum = svc.summary(for: .all)
        XCTAssertEqual(sum.counts.total, 2_000_000)
        XCTAssertEqual(sum.cost, 90.0, accuracy: 0.001)
    }

    func testRefreshIsIncrementalAndPersists() async throws {
        let (projects, storeFile) = makeDirs()
        let jsonl = projects.appendingPathComponent("Proj/session.jsonl")
        let l1 = #"{"type":"assistant","timestamp":"2026-07-12T08:00:00Z","cwd":"/P","requestId":"r1","message":{"id":"m1","model":"claude-sonnet-5","usage":{"input_tokens":10}}}"#
        try (l1 + "\n").write(to: jsonl, atomically: true, encoding: .utf8)

        let svc = TokenUsageService(projectsDir: projects, storeFileURL: storeFile)
        await svc.refresh()

        // Reload from disk in a fresh service; the cursor should prevent re-counting.
        let svc2 = TokenUsageService(projectsDir: projects, storeFileURL: storeFile)
        await svc2.refresh()
        XCTAssertEqual(svc2.summary(for: .all).counts.total, 10)
    }
}
```

**Step 2 — Verify fail.**

**Step 3 — Implement** (append to `TokenUsageService.swift`):
```swift
@MainActor
final class TokenUsageService: ObservableObject {
    @Published private(set) var hasData = false
    @Published private(set) var isScanning = false
    @Published private(set) var lastUpdated: Date?

    private var store = TokenUsageStore()
    private let projectsDir: URL
    private let storeFileURL: URL
    private let pricing: TokenPricing
    private let calendar: Calendar

    init(
        projectsDir: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true),
        storeFileURL: URL = TokenUsageService.defaultStoreURL,
        pricing: TokenPricing = TokenPricing(),
        calendar: Calendar = .current
    ) {
        self.projectsDir = projectsDir
        self.storeFileURL = storeFileURL
        self.pricing = pricing
        self.calendar = calendar
        loadStore()
    }

    static var defaultStoreURL: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/claude-usage-bar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("token-usage.json")
    }

    /// Compute a summary for a range from the in-memory store.
    func summary(for range: UsageRange, now: Date = Date()) -> UsageSummary {
        UsageSummary.compute(from: store, range: range, now: now,
                             calendar: calendar, pricing: pricing)
    }

    /// Scan the projects dir, incrementally read new bytes, ingest, persist.
    func refresh() async {
        guard FileManager.default.fileExists(atPath: projectsDir.path) else {
            hasData = false
            return
        }
        isScanning = true
        defer { isScanning = false }

        let dir = projectsDir
        var snapshot = store
        // Heavy work off the main actor.
        let updated = await Task.detached(priority: .utility) {
            Self.scan(dir: dir, into: &snapshot)
            return snapshot
        }.value

        store = updated
        hasData = !store.buckets.isEmpty
        lastUpdated = Date()
        saveStore()
    }

    /// Walk *.jsonl files, read appended bytes, parse, and ingest into the store.
    nonisolated private static func scan(dir: URL, into store: inout TokenUsageStore) {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey]) else { return }
        for case let url as URL in en where url.pathExtension == "jsonl" {
            let path = url.path
            guard let (data, cursor) = TokenUsageReader.readAppended(path: path, cursor: store.cursors[path]) else { continue }
            store.cursors[path] = cursor
            guard !data.isEmpty else { continue }
            for record in ClaudeLogParser.parseLines(data) {
                store.ingest(record)   // uses Calendar.current for day bucketing
            }
        }
    }

    private func loadStore() {
        guard let data = try? Data(contentsOf: storeFileURL) else { return }
        do {
            store = try JSONDecoder.tokenDecoder.decode(TokenUsageStore.self, from: data)
            hasData = !store.buckets.isEmpty
        } catch {
            let backup = storeFileURL.deletingPathExtension().appendingPathExtension("bak.json")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: storeFileURL, to: backup)
            store = TokenUsageStore()
        }
    }

    private func saveStore() {
        guard let data = try? JSONEncoder.tokenEncoder.encode(store) else { return }
        try? data.write(to: storeFileURL, options: .atomic)
    }
}

private extension JSONDecoder {
    static let tokenDecoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()
}
private extension JSONEncoder {
    static let tokenEncoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
}
```

> **Concurrency note:** `Task.detached` captures `snapshot` by value; `scan` mutates the copy and we assign the result back on the main actor. If the compiler flags the `inout` capture, refactor `scan` to `-> TokenUsageStore` returning the mutated copy. Keep the store a pure `Codable` value type so it crosses actor boundaries as `Sendable`.

**Step 4 — Verify pass:** `cd macos && swift test --filter TokenUsageServiceTests`.

**Step 5 — Commit:**
```bash
git add macos/Sources/ClaudeUsageBar/TokenUsageService.swift macos/Tests/ClaudeUsageBarTests/TokenUsageServiceTests.swift
git commit -m "feat: add TokenUsageService with incremental scan and persistence"
```

---

## Group E — UI

### Task 12: Token formatting helper

**Objective:** Compact token counts like `12.3M`, `45.0K`, `900`.

**Files:**
- Modify: `macos/Sources/ClaudeUsageBar/UsageSummary.swift` (add a `static func` on a small `TokenFormat` enum)
- Test: `macos/Tests/ClaudeUsageBarTests/TokenFormatTests.swift`

**Step 1 — Failing test:**
```swift
import XCTest
@testable import ClaudeUsageBar

final class TokenFormatTests: XCTestCase {
    func testCompact() {
        XCTAssertEqual(TokenFormat.compact(900), "900")
        XCTAssertEqual(TokenFormat.compact(45_000), "45.0K")
        XCTAssertEqual(TokenFormat.compact(12_300_000), "12.3M")
    }
}
```

**Step 2 — Verify fail.**

**Step 3 — Implement** (append to `UsageSummary.swift`):
```swift
enum TokenFormat {
    static func compact(_ n: Int) -> String {
        switch n {
        case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
        case 1_000...:     return String(format: "%.1fK", Double(n) / 1_000)
        default:           return "\(n)"
        }
    }
}
```

**Step 4 — Verify pass. Step 5 — Commit:**
```bash
git add macos/Sources/ClaudeUsageBar/UsageSummary.swift macos/Tests/ClaudeUsageBarTests/TokenFormatTests.swift
git commit -m "feat: add compact token formatter"
```

---

### Task 13: `TokenUsageView` — expandable section

**Objective:** Collapsed header with inline "this month" summary; expanded range picker + model/project/cache rows. (SwiftUI view; no unit test — verified by build + manual check.)

**Files:**
- Create: `macos/Sources/ClaudeUsageBar/TokenUsageView.swift`

**Step 1 — Implement:**
```swift
import SwiftUI

struct TokenUsageView: View {
    @ObservedObject var service: TokenUsageService
    @State private var expanded = false
    @State private var range: UsageRange = .month

    var body: some View {
        let monthly = service.summary(for: .month)
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text("Token & Maliyet").font(.subheadline)
                    Spacer()
                    Text(headline(monthly))
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if expanded { expandedBody }
        }
    }

    private func headline(_ s: UsageSummary) -> String {
        let dollars = s.hasUnknownModel ? "~\(ExtraUsage.formatUSD(s.cost))" : ExtraUsage.formatUSD(s.cost)
        return "Bu ay \(dollars) · \(TokenFormat.compact(s.counts.total)) tok"
    }

    @ViewBuilder private var expandedBody: some View {
        let summary = service.summary(for: range)

        Picker("", selection: $range) {
            ForEach(UsageRange.allCases) { r in Text(r.label).tag(r) }
        }
        .pickerStyle(.segmented).labelsHidden()

        HStack {
            Text(summary.hasUnknownModel ? "~\(ExtraUsage.formatUSD(summary.cost))" : ExtraUsage.formatUSD(summary.cost))
                .font(.title3).monospacedDigit()
            Spacer()
            Text("\(TokenFormat.compact(summary.counts.total)) tok")
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        Text("Notional — API pay-as-you-go fiyatıyla; abonelikte $0 ödersin.")
            .font(.caption2).foregroundStyle(.secondary)

        if !summary.byModel.isEmpty {
            sectionLabel("Model")
            ForEach(summary.byModel) { m in
                BreakdownRow(name: m.model.capitalized,
                             cost: m.cost, tokens: m.counts.total,
                             fraction: fraction(m.counts.total, summary.counts.total))
            }
        }

        if !summary.byProject.isEmpty {
            sectionLabel("Proje")
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(summary.byProject.prefix(8)) { p in
                        BreakdownRow(name: p.displayName,
                                     cost: p.cost, tokens: p.counts.total,
                                     fraction: fraction(p.counts.total, summary.counts.total))
                    }
                }
            }
            .frame(maxHeight: 140)
        }

        sectionLabel("Cache")
        HStack {
            Text("Cache-read oranı").font(.caption)
            Spacer()
            Text("\(Int((summary.cacheReadRatio * 100).rounded()))%")
                .font(.caption).monospacedDigit()
        }
        if summary.cacheSavings > 0 {
            Text("~\(ExtraUsage.formatUSD(summary.cacheSavings)) tasarruf (cache sayesinde)")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary).padding(.top, 2)
    }
    private func fraction(_ part: Int, _ whole: Int) -> Double {
        whole > 0 ? Double(part) / Double(whole) : 0
    }
}

private struct BreakdownRow: View {
    let name: String
    let cost: Double?
    let tokens: Int
    let fraction: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(name).font(.caption)
                Spacer()
                Text(cost.map { ExtraUsage.formatUSD($0) } ?? "?")
                    .font(.caption).monospacedDigit()
                Text(TokenFormat.compact(tokens))
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
            ProgressView(value: min(fraction, 1.0), total: 1.0)
                .tint(Theme.usageColor(fraction))
        }
    }
}
```

**Step 2 — Verify build:** `cd macos && swift build` → succeeds.

**Step 3 — Commit:**
```bash
git add macos/Sources/ClaudeUsageBar/TokenUsageView.swift
git commit -m "feat: add TokenUsageView expandable section"
```

---

### Task 14: Wire the section + service into the popover

**Objective:** Show `TokenUsageView` in the authenticated popover and create/refresh the service at launch.

**Files:**
- Modify: `macos/Sources/ClaudeUsageBar/ClaudeUsageBarApp.swift`
- Modify: `macos/Sources/ClaudeUsageBar/PopoverView.swift`

**Step 1 — Implement (`ClaudeUsageBarApp.swift`):**
- Add `@StateObject private var tokenUsageService = TokenUsageService()`.
- Pass it into `PopoverView(...)` (add the parameter).
- In the `.task { ... }`, after `service.startPolling()`, add: `Task { await tokenUsageService.refresh() }`.
- To keep it fresh, also refresh whenever `service.lastUpdated` changes. Simplest: add `.onChange(of: service.lastUpdated) { _, _ in Task { await tokenUsageService.refresh() } }` on the `Image` label (or refresh inside `PopoverView.onAppear`).

**Step 2 — Implement (`PopoverView.swift`):**
- Add stored property `@ObservedObject var tokenUsageService: TokenUsageService`.
- In `usageView`, before the chart divider, insert:
```swift
if tokenUsageService.hasData {
    Divider()
    TokenUsageView(service: tokenUsageService)
}
```
- Add `.onAppear { Task { await tokenUsageService.refresh() } }` to `usageView`'s root `VStack` so opening the popover recomputes with fresh data.

**Step 3 — Verify build + run:** `cd macos && swift build`; then run the app (`swift run` or the built bundle), sign in, open the popover, confirm the "Token & Maliyet" row appears with a plausible month figure and expands.

**Step 4 — Commit:**
```bash
git add macos/Sources/ClaudeUsageBar/ClaudeUsageBarApp.swift macos/Sources/ClaudeUsageBar/PopoverView.swift
git commit -m "feat: wire token usage panel into popover"
```

---

## Group F — Settings & optional remote pricing

### Task 15: Remote-pricing toggle (persisted)

**Objective:** Add a "Fiyatları uzaktan güncelle" toggle (default off) and load remote prices when enabled.

**Files:**
- Modify: `macos/Sources/ClaudeUsageBar/TokenPricing.swift` (add remote-merge + async fetch)
- Modify: `macos/Sources/ClaudeUsageBar/TokenUsageService.swift` (expose a setting + apply)
- Modify: `macos/Sources/ClaudeUsageBar/SettingsView.swift` (the toggle)
- Test: `macos/Tests/ClaudeUsageBarTests/TokenPricingTests.swift` (merge behavior only — no network in tests)

**Step 1 — Failing test** (append to `TokenPricingTests.swift`): assert a `TokenPricing(table:)` built by merging a remote dict over the bundled table prices the overridden family with the new number and leaves others intact.
```swift
    func testMergedTableOverridesFamily() {
        let remote: [String: ModelPrice] = ["opus": ModelPrice(input: 1, output: 1, cacheWrite: 1, cacheRead: 1)]
        let merged = TokenPricing(table: TokenPricing.bundledTable.merging(remote) { _, new in new })
        XCTAssertEqual(merged.cost(of: TokenCounts(input: 1), model: "claude-opus-4-8"), 1)
        XCTAssertNotNil(merged.cost(of: TokenCounts(input: 1), model: "claude-sonnet-5")) // still present
    }
```

**Step 2 — Verify fail / pass** (this may already pass given Task 3's API; if so, keep it as a regression guard and note that in the commit).

**Step 3 — Implement:**
- `SettingsView.swift`: in the "General" (or a new "Token Usage") `Section`, add:
```swift
Toggle("Fiyatları uzaktan güncelle", isOn: Binding(
    get: { service.remotePricingEnabled },
    set: { service.setRemotePricingEnabled($0) }
))
Text("Kapalıyken gömülü fiyat tablosu kullanılır (offline).")
    .font(.caption2).foregroundStyle(.secondary)
```
  (Requires passing `TokenUsageService` into `SettingsWindowContent` — add the `@ObservedObject var tokenUsageService` param and thread it from `ClaudeUsageBarApp`'s `Settings { ... }` scene.)
- `TokenUsageService`: add `@Published private(set) var remotePricingEnabled` backed by `UserDefaults` key `remotePricingEnabled`; `setRemotePricingEnabled(_:)` persists and, when enabled, launches `Task { await updatePricingFromRemote() }`. `updatePricingFromRemote()` fetches a small JSON (`[family: {input,output,cacheWrite,cacheRead perMTok}]`) from a configured URL, merges over `bundledTable`, rebuilds `pricing`, and recomputes. Keep the URL a `static let` constant; on any network error, silently keep the bundled table.

**Step 4 — Verify build + test.**

**Step 5 — Commit:**
```bash
git add -A
git commit -m "feat: add optional remote pricing update toggle"
```

---

## Group G — Finalize

### Task 16: Full suite + manual verification

**Step 1:** `cd macos && swift test` → all green (existing + new suites).
**Step 2:** `cd macos && swift build` → no warnings introduced by new files (fix any `Sendable`/actor warnings from Task 11's note).
**Step 3 — Manual (use the `verify` skill / `run` skill):** launch the app, sign in, open popover:
- "Token & Maliyet" row shows `Bu ay ~$X · Y tok`.
- Expand → range switching (Bugün/Bu ay/Tüm zamanlar) changes the numbers.
- Model rows list opus/sonnet/haiku; a Fable row (if present) shows `?` for cost but real tokens.
- Project rows list your busiest repos by token volume.
- Cache-read ratio is a sane percentage.
- Quit + relaunch → numbers persist instantly (store loaded from disk), and a refresh does not double-count (incremental cursor).
**Step 4 — Edge check:** temporarily point `TokenUsageService(projectsDir:)` at a nonexistent dir (or rename `~/.claude/projects`) in a scratch run → the section hides, no crash.

### Task 17: Commit the plan doc

```bash
git add docs/plans/2026-07-12-lokal-token-maliyet-paneli.md
git commit -m "docs: add implementation plan for local token & cost panel"
```

---

## Review checklist (before starting)

- [ ] Prices in `TokenPricing.bundledTable` verified against current Anthropic list prices.
- [ ] Decide whether to include Task 9b (per-project cost) up front or defer.
- [ ] Confirm remote-pricing JSON URL/shape (Task 15) or drop remote update to a later pass and ship bundled-only.
- [ ] `swift test` and `swift build` both green.
- [ ] No changes to `UsageService`/OAuth beyond the documented wiring.
