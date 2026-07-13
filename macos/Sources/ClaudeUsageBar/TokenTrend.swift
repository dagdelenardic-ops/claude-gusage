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

/// Current vs previous calendar period (week or month).
struct PeriodComparison: Equatable {
    let currentCost: Double
    let previousCost: Double
    let currentTokens: Int
    let previousTokens: Int
    /// (current − previous) / previous; nil when the previous period is empty.
    var costDeltaRatio: Double? {
        previousCost > 0 ? (currentCost - previousCost) / previousCost : nil
    }
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

    static func weekComparison(
        from store: TokenUsageStore, now: Date,
        calendar: Calendar = .current, pricing: TokenPricing
    ) -> PeriodComparison {
        comparison(from: store, component: .weekOfYear, now: now, calendar: calendar, pricing: pricing)
    }

    static func monthComparison(
        from store: TokenUsageStore, now: Date,
        calendar: Calendar = .current, pricing: TokenPricing
    ) -> PeriodComparison {
        comparison(from: store, component: .month, now: now, calendar: calendar, pricing: pricing)
    }

    private static func comparison(
        from store: TokenUsageStore,
        component: Calendar.Component,
        now: Date,
        calendar: Calendar,
        pricing: TokenPricing
    ) -> PeriodComparison {
        guard
            let current = calendar.dateInterval(of: component, for: now),
            let previousRef = calendar.date(byAdding: component, value: -1, to: now),
            let previous = calendar.dateInterval(of: component, for: previousRef)
        else {
            return PeriodComparison(currentCost: 0, previousCost: 0, currentTokens: 0, previousTokens: 0)
        }
        let cur = total(in: current, store: store, calendar: calendar, pricing: pricing)
        let prev = total(in: previous, store: store, calendar: calendar, pricing: pricing)
        return PeriodComparison(currentCost: cur.cost, previousCost: prev.cost,
                                currentTokens: cur.counts.total, previousTokens: prev.counts.total)
    }

    private static func total(
        in interval: DateInterval,
        store: TokenUsageStore,
        calendar: Calendar,
        pricing: TokenPricing
    ) -> (counts: TokenCounts, cost: Double) {
        var counts = TokenCounts()
        var cost = 0.0
        var date = interval.start
        while date < interval.end {
            let key = TokenUsageStore.dayKey(date, calendar: calendar)
            let day = aggregate(store.buckets[key], pricing: pricing)
            counts = counts + day.counts
            cost += day.cost
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
        return (counts, cost)
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
