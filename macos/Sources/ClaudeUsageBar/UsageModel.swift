import Foundation

struct UsageResponse: Codable {
    let fiveHour: UsageBucket?
    let sevenDay: UsageBucket?
    let sevenDayOpus: UsageBucket?
    let sevenDaySonnet: UsageBucket?
    let claudeDesign: UsageBucket?
    let dailyRoutineRuns: RoutineRunsBucket?
    let extraUsage: ExtraUsage?
    /// Live, per-scope limit entries. The API moved the authoritative data here —
    /// including model-scoped limits (e.g. Fable) that have no dedicated bucket.
    let limits: [UsageLimit]?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
        case claudeDesign = "seven_day_omelette"
        case dailyRoutineRuns = "daily_routine_runs"
        case extraUsage = "extra_usage"
        case limits
    }

    func reconciled(with previous: UsageResponse?, now: Date = Date()) -> UsageResponse {
        UsageResponse(
            fiveHour: fiveHour?.reconciled(
                with: previous?.fiveHour,
                resetInterval: 5 * 60 * 60,
                now: now
            ),
            sevenDay: sevenDay?.reconciled(
                with: previous?.sevenDay,
                resetInterval: 7 * 24 * 60 * 60,
                now: now
            ),
            sevenDayOpus: sevenDayOpus?.reconciled(
                with: previous?.sevenDayOpus,
                resetInterval: 7 * 24 * 60 * 60,
                now: now
            ),
            sevenDaySonnet: sevenDaySonnet?.reconciled(
                with: previous?.sevenDaySonnet,
                resetInterval: 7 * 24 * 60 * 60,
                now: now
            ),
            claudeDesign: claudeDesign?.reconciled(
                with: previous?.claudeDesign,
                resetInterval: 7 * 24 * 60 * 60,
                now: now
            ),
            dailyRoutineRuns: dailyRoutineRuns?.reconciled(
                with: previous?.dailyRoutineRuns,
                resetInterval: 24 * 60 * 60,
                now: now
            ),
            extraUsage: extraUsage,
            // Limits already carry their own resets_at from the server; pass through unchanged.
            limits: limits
        )
    }

    /// Limit entries scoped to a specific model/surface (e.g. Fable) — these have
    /// no named bucket, so they are otherwise invisible in the UI.
    var scopedLimits: [UsageLimit] {
        (limits ?? []).filter { $0.scope?.isMeaningful ?? false }
    }
}

/// A single live limit entry from the `limits` array.
struct UsageLimit: Codable, Identifiable {
    let kind: String?
    let group: String?
    let percent: Double?
    let severity: String?
    let resetsAt: String?
    let scope: LimitScope?
    let isActive: Bool?

    enum CodingKeys: String, CodingKey {
        case kind, group, percent, severity, scope
        case resetsAt = "resets_at"
        case isActive = "is_active"
    }

    var id: String {
        let scopePart = scope?.model?.displayName ?? scope?.surface ?? ""
        return "\(kind ?? "")|\(group ?? "")|\(scopePart)"
    }

    var resetsAtDate: Date? {
        UsageBucket.parseResetDate(from: resetsAt)
    }

    var isCritical: Bool {
        severity?.lowercased() == "critical"
    }

    /// Human label: prefer the scoped model name (e.g. "Fable"), then surface, then kind.
    var displayLabel: String {
        if let name = scope?.model?.displayName, !name.isEmpty { return name }
        if let surface = scope?.surface, !surface.isEmpty { return surface }
        return kind ?? "Limit"
    }

    var percentText: String {
        guard let percent else { return "—" }
        return "\(Int(percent.rounded()))%"
    }
}

struct LimitScope: Codable {
    let model: LimitModel?
    let surface: String?

    /// True when the scope actually narrows to a model or surface (not an empty `{}`).
    var isMeaningful: Bool {
        (model?.displayName?.isEmpty == false) || (surface?.isEmpty == false)
    }
}

struct LimitModel: Codable {
    let id: String?
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }
}

struct UsageBucket: Codable {
    let utilization: Double?
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    var resetsAtDate: Date? {
        Self.parseResetDate(from: resetsAt)
    }

    func reconciled(with previous: UsageBucket?, resetInterval: TimeInterval, now: Date) -> UsageBucket {
        guard resetsAtDate == nil else { return self }
        guard let previousDate = previous?.resetsAtDate else { return self }

        let resolvedDate = Self.nextResetDate(
            from: previousDate,
            resetInterval: resetInterval,
            now: now
        )

        return UsageBucket(
            utilization: utilization,
            resetsAt: Self.resetString(from: resolvedDate)
        )
    }

    static func parseResetDate(from value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }

        let isoFormatters: [ISO8601DateFormatter.Options] = [
            [.withInternetDateTime, .withFractionalSeconds],
            [.withInternetDateTime]
        ]

        for options in isoFormatters {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = options
            if let date = formatter.date(from: value) {
                return date
            }
        }

        let fallbackPatterns = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSS",
            "yyyy-MM-dd'T'HH:mm:ss.SSS",
            "yyyy-MM-dd'T'HH:mm:ss"
        ]

        for pattern in fallbackPatterns {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = pattern
            if let date = formatter.date(from: value) {
                return date
            }
        }

        return nil
    }

    static func nextResetDate(from previous: Date, resetInterval: TimeInterval, now: Date) -> Date {
        guard resetInterval > 0 else { return previous }
        guard previous <= now else { return previous }

        let elapsed = now.timeIntervalSince(previous)
        let stepCount = floor(elapsed / resetInterval) + 1
        return previous.addingTimeInterval(stepCount * resetInterval)
    }

    static func resetString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

struct ExtraUsage: Codable {
    let isEnabled: Bool
    let utilization: Double?
    let usedCredits: Double?
    let monthlyLimit: Double?

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case utilization
        case usedCredits = "used_credits"
        case monthlyLimit = "monthly_limit"
    }

    /// API returns credits in minor units (cents); convert to dollars.
    var usedCreditsAmount: Double? {
        usedCredits.map { $0 / 100.0 }
    }

    var monthlyLimitAmount: Double? {
        monthlyLimit.map { $0 / 100.0 }
    }

    static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f
    }()

    static func formatUSD(_ amount: Double) -> String {
        currencyFormatter.string(from: NSNumber(value: amount))
            ?? String(format: "$%.2f", amount)
    }
}

struct RoutineRunsBucket: Codable {
    let used: Int?
    let total: Int?
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case used
        case total
        case resetsAt = "resets_at"
    }

    var resetsAtDate: Date? {
        UsageBucket.parseResetDate(from: resetsAt)
    }

    var utilization: Double? {
        guard let used, let total, total > 0 else { return nil }
        return Double(used) / Double(total) * 100.0
    }

    func reconciled(with previous: RoutineRunsBucket?, resetInterval: TimeInterval, now: Date) -> RoutineRunsBucket {
        guard resetsAtDate == nil else { return self }
        guard let previousDate = previous?.resetsAtDate else { return self }

        let resolvedDate = UsageBucket.nextResetDate(
            from: previousDate,
            resetInterval: resetInterval,
            now: now
        )

        return RoutineRunsBucket(
            used: used,
            total: total,
            resetsAt: UsageBucket.resetString(from: resolvedDate)
        )
    }
}
