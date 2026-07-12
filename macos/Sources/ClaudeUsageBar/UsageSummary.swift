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

enum TokenFormat {
    static func compact(_ n: Int) -> String {
        switch n {
        case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
        case 1_000...:     return String(format: "%.1fK", Double(n) / 1_000)
        default:           return "\(n)"
        }
    }
}
