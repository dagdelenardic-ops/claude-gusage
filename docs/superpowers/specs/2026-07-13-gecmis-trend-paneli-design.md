# Tasarım: Geçmiş & Trend Paneli

**Tarih:** 2026-07-13
**Durum:** Onaylandı
**Faz:** 2/4 (yol haritasının ikinci parçası)

## Bağlam

Faz 1 lokal token & maliyet panelini kurdu: `TokenUsageStore.buckets`
gün-anahtarlı (`"yyyy-MM-dd" → model ailesi → proje → TokenCounts`) ve
`~/.config/claude-usage-bar/token-usage.json`'da kalıcı. Loglar silinse
bile bir kez ingest edilen günün verisi store'da kalır.

Roadmap'in "lokal token'ı history'e yaz" varsayımı bu yüzden **geçersiz
çıktı**: geçmiş zaten yazılıyor. Faz 2 salt okuma tarafıdır — gün serisi
çıkaran bir reduction + bar chart + hafta/ay karşılaştırması.

Fiyatlar Faz 1 sonrası güncellendi (Opus 5/25, Sonnet 3/15, Haiku 1/5,
Fable 10/50); günlük maliyet bu tabloyla hesaplanır.

## Amaç

Token & Maliyet panelinin genişletilmiş görünümüne **Trend** bölümü:

1. Son 7 / 30 günün **günlük notional maliyeti** bar chart olarak
2. Hover'da gün + $ + token detayı
3. **Bu hafta vs geçen hafta** ve **bu ay vs geçen ay** karşılaştırma
   satırları (maliyet, token, yüzde değişim)

## Değerlendirilen yaklaşımlar

- **A (seçilen):** Ayrı `TokenTrend` reduction + `TokenTrendView`.
  OAuth grafiğine (`UsageChartView`/`UsageHistoryService`) dokunulmaz.
  Swift Charts zaten bağımlılıkta (macOS 14), `BarMark` hazır.
- B: Token serisini `UsageHistoryService`'e eklemek — veri modeli
  uyumsuz (5 dk'lık örnekleme noktaları vs gün bucket'ları), OAuth kod
  yoluna dokunur. Reddedildi.
- C: Ayrı grafik penceresi — popover uygulaması için fazla (YAGNI).

## Mimari

Yeni iki dosya + tek noktadan wiring; mevcut dosyalarda davranış
değişikliği yok.

### 1. `TokenTrend.swift` (Foundation-only)

```swift
struct DailyUsage: Identifiable, Equatable {
    let day: String        // "yyyy-MM-dd"
    let date: Date         // günün başlangıcı (grafik X ekseni)
    let counts: TokenCounts
    let cost: Double       // bilinen modellerin toplamı (unknown hariç)
    let hasUnknownModel: Bool
    var id: String { day }
}

struct PeriodComparison: Equatable {
    let currentCost: Double, previousCost: Double
    let currentTokens: Int, previousTokens: Int
    /// (current-previous)/previous; previous 0 iken nil ("yeni" durumu).
    var costDeltaRatio: Double? { ... }
}

enum TokenTrend {
    /// Son `days` günün serisi, bugün dahil, eskiden yeniye.
    /// Store'da olmayan günler sıfır sayaçlarla doldurulur.
    static func daily(from store: TokenUsageStore, days: Int, now: Date,
                      calendar: Calendar, pricing: TokenPricing) -> [DailyUsage]

    /// Takvim sınırlı karşılaştırma: `.weekOfYear` (locale'e göre —
    /// TR'de Pazartesi başlar) ve `.month`. "Şu ana kadar" değil,
    /// tam önceki dönem vs içinde bulunulan dönem.
    static func weekComparison(from:now:calendar:pricing:) -> PeriodComparison
    static func monthComparison(from:now:calendar:pricing:) -> PeriodComparison
}
```

Kararlar:
- **Bar metriği maliyettir** ($). Token değeri hover/karşılaştırmada
  gösterilir. Fiyatsız modelin token'ı günlük maliyete katılmaz;
  `hasUnknownModel` işaretlenir (gerçek veride şu an hepsi fiyatlı).
- Gün anahtarı üretimi `TokenUsageStore.dayKey` ile birebir aynı
  (yerel takvim) — ingest ile okuma aynı bucketing'i kullanır.
- Karşılaştırma dönem tanımı `calendar.dateInterval(of:for:)` iledir;
  hafta başlangıcı locale'den gelir, elle Pazartesi kodlanmaz.

### 2. `TokenTrendView.swift` (SwiftUI + Charts)

- 7g / 30g segmented picker (`@State`, varsayılan 7g)
- `Chart { BarMark(x: gün, y: maliyet) }`; bar rengi `Theme.accent`,
  hover'da `RuleMark` + annotation: "12 Tem · $23.40 · 61.2M tok"
  (mevcut `UsageChartView` hover desenini izler, `chartOverlay` ile)
- Y ekseni $; tüm seri sıfırsa "Henüz trend verisi yok." boş durumu
- Altında iki satır:
  - `Bu hafta $X · geçen hafta $Y (↑%Z)` — delta işareti yön okuyla,
    previous 0 ise yüzde yerine "yeni"
  - Aynısı ay için
- Yükseklik ~120pt; popover genişliğine sığar

### 3. Wiring

`TokenUsageView.expandedBody` içine, range picker'lı özet bloğunun
altına ve "Model" bölümünün üstüne `sectionLabel("Trend")` +
`TokenTrendView`. `TokenTrendView`'a store erişimi
`TokenUsageService.summary(...)` benzeri yeni bir geçitle verilir:

```swift
// TokenUsageService
func dailyTrend(days: Int, now: Date = Date()) -> [DailyUsage]
func weekComparison(now: Date = Date()) -> PeriodComparison
func monthComparison(now: Date = Date()) -> PeriodComparison
```

Böylece `store` private kalır ve view saf veriyle çalışır.

## Hata durumları

- Boş store / kapsam dışı günler → sıfır dolgulu seri, boş-durum metni
- Tek günlük veri → tek bar (crash yok, ölçek 0'dan başlar)
- `previousCost == 0` → yüzde hesaplanmaz, "yeni" gösterilir
- Gün/ay sınırında saat dilimi: tüm hesaplar `Calendar.current`
  (ingest ile aynı takvim) üzerinden; test'lerde UTC sabitlenir

## Test stratejisi

- `TokenTrendTests` (XCTest, Xcode'lu makinede koşar):
  - boş gün doldurma (7 günlük seride 3 dolu 4 sıfır)
  - seri sıralaması eskiden yeniye, bugün dahil
  - hafta sınırı: Pazar/Pazartesi kayıtları doğru döneme düşer
  - ay karşılaştırması + delta; previous 0 → nil
  - fiyatsız model günlük maliyete katılmaz, bayrak set edilir
- Bu ortamda (Xcode yok): aynı senaryolar swiftc harness ile GREEN
  kanıtlanır; gerçek `~/.claude/projects` verisinde uçtan uca duman testi
- `swift build` sıfır uyarı

## Kapsam dışı

- Burn-rate & tükenme projeksiyonu (Faz 3)
- Menu bar görünüm modları (Faz 4)
- OAuth grafiğinde (`UsageChartView`) her türlü değişiklik
- Proje/model bazlı trend kırılımı (gerekirse Faz 2.5)
