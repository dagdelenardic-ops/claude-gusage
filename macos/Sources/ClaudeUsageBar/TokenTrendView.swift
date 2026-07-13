import SwiftUI
import Charts

struct TokenTrendView: View {
    @ObservedObject var service: TokenUsageService
    @State private var days = 7
    @State private var hoveredDay: DailyUsage?

    var body: some View {
        let series = service.dailyTrend(days: days)
        VStack(alignment: .leading, spacing: 6) {
            Picker("", selection: $days) {
                Text("7g").tag(7)
                Text("30g").tag(30)
            }
            .pickerStyle(.segmented).labelsHidden()

            if series.allSatisfy({ $0.counts.total == 0 }) {
                Text("Henüz trend verisi yok.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
            } else {
                chart(series)
                Text(hoverDetail(series))
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }

            comparisonRow(label: "Bu hafta", c: service.weekComparison())
            comparisonRow(label: "Bu ay", c: service.monthComparison())
        }
    }

    /// Hovered day if any, otherwise today's summary keeps the line height stable.
    private func hoverDetail(_ series: [DailyUsage]) -> String {
        guard let d = hoveredDay ?? series.last else { return "" }
        let date = d.date.formatted(.dateTime.day().month())
        let cost = d.hasUnknownModel ? "~\(ExtraUsage.formatUSD(d.cost))" : ExtraUsage.formatUSD(d.cost)
        return "\(date) · \(cost) · \(TokenFormat.compact(d.counts.total)) tok"
    }

    private func chart(_ series: [DailyUsage]) -> some View {
        Chart(series) { day in
            BarMark(
                x: .value("Gün", day.date, unit: .day),
                y: .value("Maliyet", day.cost)
            )
            .foregroundStyle(day.day == hoveredDay?.day ? Theme.accentStrong : Theme.accent)
        }
        .frame(height: 110)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard let plotFrame = proxy.plotFrame else { return }
                            let x = location.x - geo[plotFrame].origin.x
                            if let date: Date = proxy.value(atX: x) {
                                let key = TokenUsageStore.dayKey(date)
                                hoveredDay = series.first { $0.day == key }
                            }
                        case .ended:
                            hoveredDay = nil
                        }
                    }
            }
        }
    }

    private func comparisonRow(label: String, c: PeriodComparison) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption)
            Spacer()
            Text("\(ExtraUsage.formatUSD(c.currentCost)) · önceki \(ExtraUsage.formatUSD(c.previousCost))")
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            deltaBadge(c)
        }
    }

    @ViewBuilder private func deltaBadge(_ c: PeriodComparison) -> some View {
        if let r = c.costDeltaRatio {
            Text("\(r >= 0 ? "↑" : "↓")%\(Int((abs(r) * 100).rounded()))")
                .font(.caption2).monospacedDigit()
                .foregroundStyle(r >= 0 ? Theme.accentStrong : .secondary)
        } else if c.currentCost > 0 {
            Text("yeni").font(.caption2).foregroundStyle(.secondary)
        }
    }
}
