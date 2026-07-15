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

enum UsageRange: String, CaseIterable, Identifiable {
    case today, month, all
    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: return "Today"
        case .month: return "This month"
        case .all:   return "All time"
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
