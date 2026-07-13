import Foundation

/// One day of aggregated local usage, for trend charts.
struct DailyUsage: Identifiable, Equatable {
    let day: String        // "yyyy-MM-dd", same keying as TokenUsageStore.dayKey
    let date: Date         // start of day (chart X axis)
    let counts: TokenCounts
    let cost: Double       // known-model total; unpriced models excluded
    let hasUnknownModel: Bool
    var id: String { day }
}

enum TokenTrend {
    /// Series for the last `days` days including today, oldest first.
    /// Days absent from the store are filled with zero counts.
    static func daily(
        from store: TokenUsageStore,
        days: Int,
        now: Date,
        calendar: Calendar = .current,
        pricing: TokenPricing
    ) -> [DailyUsage] {
        let startOfToday = calendar.startOfDay(for: now)
        return (0..<days).reversed().compactMap { back in
            guard let date = calendar.date(byAdding: .day, value: -back, to: startOfToday) else { return nil }
            let day = TokenUsageStore.dayKey(date, calendar: calendar)
            let (counts, cost, hasUnknown) = aggregate(store.buckets[day], pricing: pricing)
            return DailyUsage(day: day, date: date, counts: counts, cost: cost, hasUnknownModel: hasUnknown)
        }
    }

    /// Sum one day-bucket across models/projects; price known models only.
    static func aggregate(
        _ dayBucket: [String: [String: TokenCounts]]?,
        pricing: TokenPricing
    ) -> (counts: TokenCounts, cost: Double, hasUnknown: Bool) {
        var counts = TokenCounts()
        var cost = 0.0
        var hasUnknown = false
        for (model, projects) in dayBucket ?? [:] {
            for (_, c) in projects {
                counts = counts + c
                if let dollars = pricing.cost(of: c, model: model) {
                    cost += dollars
                } else {
                    hasUnknown = true
                }
            }
        }
        return (counts, cost, hasUnknown)
    }
}
