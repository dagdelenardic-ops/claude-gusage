# Geçmiş & Trend Paneli — İmplementasyon Planı

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Token & Maliyet paneline günlük maliyet bar chart'ı (7g/30g) ve hafta/ay karşılaştırma satırları eklemek.

**Architecture:** `TokenUsageStore.buckets` zaten gün-anahtarlı; yeni `TokenTrend` (Foundation-only reduction) gün serisi ve dönem karşılaştırması üretir, `TokenTrendView` (SwiftUI + Charts `BarMark`) çizer, `TokenUsageService` üç geçit metodu ekler, `TokenUsageView.expandedBody`'ye "Trend" bölümü olarak bağlanır. OAuth grafiğine dokunulmaz.

**Tech Stack:** Swift 5.9, SwiftUI, Swift Charts (macOS 14), XCTest (Xcode'lu makinede) + swiftc harness (bu ortamda).

**Ortam notu:** Bu makinede Xcode yok → `swift test` çalışmaz. Her görevde "test çalıştır" adımı: XCTest dosyasını yaz (gelecekte koşacak) **ve** aynı senaryoyu swiftc harness'e ekleyip koştur. Harness derleme komutu Task 6'da.

**Spec:** `docs/superpowers/specs/2026-07-13-gecmis-trend-paneli-design.md`

---

### Task 1: TokenTrend.daily — gün serisi reduction

**Objective:** Son N günün sıfır-dolgulu, eskiden-yeniye günlük kullanım serisini üreten saf fonksiyon.

**Files:**
- Create: `macos/Sources/ClaudeUsageBar/TokenTrend.swift`
- Test: `macos/Tests/ClaudeUsageBarTests/TokenTrendTests.swift`

**Step 1: Failing test'i yaz** (`TokenTrendTests.swift`, yeni dosya):

```swift
import XCTest
@testable import ClaudeUsageBar

final class TokenTrendTests: XCTestCase {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2 // Pazartesi — deterministik hafta sınırı
        return c
    }

    private func rec(_ k: String, _ iso: String, _ model: String = "claude-opus-4-8",
                     _ proj: String = "/P", _ counts: TokenCounts) -> UsageRecord {
        UsageRecord(timestamp: UsageBucket.parseResetDate(from: iso)!,
                    model: model, project: proj, counts: counts, dedupKey: k)
    }

    func testDailyFillsMissingDaysOldestFirst() {
        var s = TokenUsageStore()
        // 2026-07-15 Çarşamba. Dolu günler: 13 ve 15; 09..12 ve 14 boş.
        s.ingest(rec("1", "2026-07-13T10:00:00Z", counts: TokenCounts(input: 1_000_000)), calendar: utc)
        s.ingest(rec("2", "2026-07-15T08:00:00Z", counts: TokenCounts(output: 1_000_000)), calendar: utc)
        let now = UsageBucket.parseResetDate(from: "2026-07-15T12:00:00Z")!

        let series = TokenTrend.daily(from: s, days: 7, now: now, calendar: utc, pricing: TokenPricing())

        XCTAssertEqual(series.count, 7)
        XCTAssertEqual(series.first?.day, "2026-07-09")          // en eski başta
        XCTAssertEqual(series.last?.day, "2026-07-15")           // bugün sonda
        XCTAssertEqual(series.first?.counts.total, 0)            // boş gün sıfır
        XCTAssertEqual(series[4].day, "2026-07-13")
        XCTAssertEqual(series[4].counts.total, 1_000_000)
        XCTAssertEqual(series[4].cost, 5.0, accuracy: 0.001)     // opus 1M input × $5/MTok
        XCTAssertEqual(series.last!.cost, 25.0, accuracy: 0.001) // opus 1M output × $25/MTok
    }

    func testDailyExcludesUnpricedModelFromCostAndFlags() {
        var s = TokenUsageStore()
        s.ingest(rec("1", "2026-07-15T08:00:00Z", counts: TokenCounts(input: 1_000_000)), calendar: utc)
        s.ingest(rec("2", "2026-07-15T09:00:00Z", "<synthetic>", counts: TokenCounts(input: 500)), calendar: utc)
        let now = UsageBucket.parseResetDate(from: "2026-07-15T12:00:00Z")!

        let today = TokenTrend.daily(from: s, days: 1, now: now, calendar: utc, pricing: TokenPricing()).last!
        XCTAssertEqual(today.counts.total, 1_000_500)   // token yine sayılır
        XCTAssertEqual(today.cost, 5.0, accuracy: 0.001) // fiyatsız model $'a katılmaz
        XCTAssertTrue(today.hasUnknownModel)
    }
}
```

**Step 2:** Derlemeyi dene: `cd macos && swift build` → beklenen: FAIL — `TokenTrend` yok. (Test hedefi burada koşamıyor; RED kanıtı Task 6 harness'inde de alınacak.)

**Step 3: Minimal implementasyon** — `TokenTrend.swift` (yeni dosya, tam içerik):

```swift
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
```

**Step 4:** `cd macos && swift build` → beklenen: `Build complete!` sıfır uyarı.

**Step 5: Commit**

```bash
git add macos/Sources/ClaudeUsageBar/TokenTrend.swift macos/Tests/ClaudeUsageBarTests/TokenTrendTests.swift
git commit -m "feat: add TokenTrend daily series reduction"
```

---

### Task 2: PeriodComparison — hafta/ay karşılaştırması

**Objective:** Takvim sınırlı "bu dönem vs önceki dönem" maliyet/token karşılaştırması.

**Files:**
- Modify: `macos/Sources/ClaudeUsageBar/TokenTrend.swift` (sona ekle)
- Modify: `macos/Tests/ClaudeUsageBarTests/TokenTrendTests.swift` (sona ekle)

**Step 1: Failing testleri yaz** (TokenTrendTests sınıfına ekle):

```swift
    func testWeekComparisonUsesCalendarWeekBoundary() {
        var s = TokenUsageStore()
        // 2026-07-15 Çarşamba; hafta Pzt 13 – Paz 19. Önceki hafta Pzt 6 – Paz 12.
        s.ingest(rec("1", "2026-07-14T10:00:00Z", counts: TokenCounts(input: 1_000_000)), calendar: utc)   // bu hafta: $5
        s.ingest(rec("2", "2026-07-12T10:00:00Z", counts: TokenCounts(input: 2_000_000)), calendar: utc)   // geçen hafta (Pazar): $10
        s.ingest(rec("3", "2026-07-05T10:00:00Z", counts: TokenCounts(input: 8_000_000)), calendar: utc)   // 2 hafta önce: dahil değil
        let now = UsageBucket.parseResetDate(from: "2026-07-15T12:00:00Z")!

        let c = TokenTrend.weekComparison(from: s, now: now, calendar: utc, pricing: TokenPricing())
        XCTAssertEqual(c.currentCost, 5.0, accuracy: 0.001)
        XCTAssertEqual(c.previousCost, 10.0, accuracy: 0.001)
        XCTAssertEqual(c.currentTokens, 1_000_000)
        XCTAssertEqual(c.previousTokens, 2_000_000)
        XCTAssertEqual(c.costDeltaRatio!, -0.5, accuracy: 0.001)
    }

    func testMonthComparisonAndNewPeriod() {
        var s = TokenUsageStore()
        s.ingest(rec("1", "2026-07-10T10:00:00Z", counts: TokenCounts(input: 1_000_000)), calendar: utc)  // Temmuz: $5
        let now = UsageBucket.parseResetDate(from: "2026-07-15T12:00:00Z")!

        let c = TokenTrend.monthComparison(from: s, now: now, calendar: utc, pricing: TokenPricing())
        XCTAssertEqual(c.currentCost, 5.0, accuracy: 0.001)
        XCTAssertEqual(c.previousCost, 0.0, accuracy: 0.001)   // Haziran boş
        XCTAssertNil(c.costDeltaRatio)                          // önceki 0 → "yeni"
    }
```

**Step 2:** `swift build` → FAIL — `weekComparison` yok.

**Step 3: İmplementasyon** — `TokenTrend.swift`'e ekle:

```swift
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

extension TokenTrend {
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
}
```

Not: `calendar.date(byAdding: .weekOfYear, value: -1, ...)` geçerli bir `Calendar.Component` eklemesidir; ay için `.month`. `component` parametresi her iki çağrıda da doğrudan kullanılabilir.

**Step 4:** `swift build` → `Build complete!`.

**Step 5: Commit**

```bash
git add macos/Sources/ClaudeUsageBar/TokenTrend.swift macos/Tests/ClaudeUsageBarTests/TokenTrendTests.swift
git commit -m "feat: add week/month period comparison to TokenTrend"
```

---

### Task 3: TokenUsageService geçitleri

**Objective:** View'ın private `store`'a dokunmadan trend verisi alabilmesi.

**Files:**
- Modify: `macos/Sources/ClaudeUsageBar/TokenUsageService.swift` — `summary(for:now:)` metodunun hemen altına ekle

**Step 1: İmplementasyon:**

```swift
    /// Daily series for the trend chart, oldest first, zero-filled.
    func dailyTrend(days: Int, now: Date = Date()) -> [DailyUsage] {
        TokenTrend.daily(from: store, days: days, now: now, calendar: calendar, pricing: pricing)
    }

    func weekComparison(now: Date = Date()) -> PeriodComparison {
        TokenTrend.weekComparison(from: store, now: now, calendar: calendar, pricing: pricing)
    }

    func monthComparison(now: Date = Date()) -> PeriodComparison {
        TokenTrend.monthComparison(from: store, now: now, calendar: calendar, pricing: pricing)
    }
```

**Step 2:** `swift build` → `Build complete!`.

**Step 3: Commit**

```bash
git add macos/Sources/ClaudeUsageBar/TokenUsageService.swift
git commit -m "feat: expose trend gateways on TokenUsageService"
```

---

### Task 4: TokenTrendView — bar chart + karşılaştırma satırları

**Objective:** 7g/30g günlük maliyet bar chart'ı, hover detayı ve iki karşılaştırma satırı.

**Files:**
- Create: `macos/Sources/ClaudeUsageBar/TokenTrendView.swift` (tam içerik)

**Step 1: İmplementasyon:**

```swift
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
        let d = hoveredDay ?? series.last!
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
```

Notlar:
- `proxy.plotFrame` macOS 14 Charts API'sidir (`plotAreaFrame` deprecated).
- Hover satırı her zaman görünür (hover yokken bugünün özeti) — yükseklik zıplamasın.
- Delta rengi: artış `Theme.accentStrong` (harcama artışı dikkat rengi), düşüş nötr.

**Step 2:** `swift build` → `Build complete!` sıfır uyarı. Uyarı çıkarsa (ör. `plotFrame` opsiyoneli) düzelt.

**Step 3: Commit**

```bash
git add macos/Sources/ClaudeUsageBar/TokenTrendView.swift
git commit -m "feat: add TokenTrendView bar chart with period comparisons"
```

---

### Task 5: TokenUsageView wiring

**Objective:** Trend bölümünü panelin genişletilmiş gövdesine bağlamak.

**Files:**
- Modify: `macos/Sources/ClaudeUsageBar/TokenUsageView.swift` — `expandedBody` içinde, "Notional —..." satırı ile `if !summary.byModel.isEmpty` bloğu arasına:

**Step 1: Ekle:**

```swift
        sectionLabel("Trend")
        TokenTrendView(service: service)
```

**Step 2:** `swift build` → `Build complete!`.

**Step 3: Commit**

```bash
git add macos/Sources/ClaudeUsageBar/TokenUsageView.swift
git commit -m "feat: wire trend section into token usage panel"
```

---

### Task 6: Harness doğrulaması + gerçek veri duman testi

**Objective:** XCTest koşamayan bu ortamda çekirdek matematiği kanıtlamak.

**Files:**
- Create (scratchpad, commit edilmez): `<scratchpad>/trend/main.swift`

**Step 1: Harness yaz** — Task 1–2'deki test senaryolarının birebir assert karşılıkları: 7 günlük sıfır dolgu + sıralama, fiyatsız model dışlama, hafta sınırı (−%50 delta), ay karşılaştırması (previous 0 → nil). Ek: gerçek `~/.claude/projects` üzerinde son 7 günün serisini ve hafta/ay karşılaştırmasını yazdır (değerler sıfır değil ve gün sayısı doğru olmalı).

**Step 2: Derle + koştur:**

```bash
SRC=macos/Sources/ClaudeUsageBar
swiftc -O -o "$SCRATCH/trend/run" \
  "$SRC/TokenUsageModel.swift" "$SRC/TokenUsageStore.swift" \
  "$SRC/TokenPricing.swift" "$SRC/UsageSummary.swift" \
  "$SRC/TokenTrend.swift" "$SRC/ClaudeLogParser.swift" "$SRC/UsageModel.swift" \
  "$SCRATCH/trend/main.swift"
"$SCRATCH/trend/run"
```

Beklenen: tüm assert'ler PASS + gerçek veride makul seri.

**Step 3:** Sonuçları özete geçir. Commit yok (harness scratchpad'de kalır).

---

### Task 7: Kapanış

- `swift build` son kontrol (sıfır uyarı), `git status` temiz
- Roadmap memory güncelle: Faz 2 ✅, sıradaki Faz 3 (burn-rate)
- Kullanıcı özeti: GUI manuel kontrol + `swift test` hâlâ Xcode'lu makinede bekliyor
