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

        sectionLabel("Trend")
        TokenTrendView(service: service)

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
