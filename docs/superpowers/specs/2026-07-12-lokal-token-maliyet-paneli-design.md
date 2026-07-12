# Tasarım: Lokal Token & Maliyet Paneli

**Tarih:** 2026-07-12
**Durum:** Onaylandı (implementasyon planı bekleniyor)
**Faz:** 1/4 (yol haritasının ilk parçası)

## Bağlam

Claude Usage Bar şu an abonelik kota-yüzdesi API'sini (`/api/oauth/usage`)
neredeyse tamamen tüketiyor: 5 saatlik oturum, 7 günlük haftalık limitler,
model bazlı limitler (Opus/Sonnet/Design/Fable), günlük routine runs ve
extra-usage kredileri. Bu API'de sıkacak yeni ham alan kalmadı.

Kullanılmayan asıl veri kaynağı **lokal Claude Code loglarıdır**
(`~/.claude/projects/*/*.jsonl`). Her assistant mesajı gerçek token
tüketimini içerir. Bu spec, bu kaynaktan bir "mini-ccusage" paneli üretir.

Bu, dört fazlı yol haritasının ilk fazıdır:

| # | Özellik | Efor |
|---|---|---|
| **1** | **Lokal token & maliyet motoru (bu spec)** | Yüksek |
| 2 | Geçmiş & trend genişletme | Orta |
| 3 | Burn rate & tükenme projeksiyonu | Düşük |
| 4 | Menu bar görünüm modları | Düşük |

## Amaç

Kota-yüzdesi bar'larının yanına, lokal loglardan hesaplanan **gerçek
kullanım** metriği eklemek:

1. Ne kadar token yakıldığı (input / output / cache-create / cache-read)
2. *Notional* $ maliyeti — abonelikte cebten $0 çıkar; bu rakam "aynı kullanım
   API pay-as-you-go'da ne ederdi" demektir ve UI'da açıkça belirtilir
3. Hangi **proje** ve hangi **modelin** yaktığı (atıf)
4. **Cache verimliliği** — cache-read oranı ve tahmini tasarruf

Ana odak (kullanıcı kararı): maliyet ($), proje/model atfı, cache verimliliği.
Aktivite ritmi/heatmap **kapsam dışıdır** (Faz 2+).

## Veri Kaynağı

`~/.claude/projects/<encoded-project>/<session-uuid>.jsonl` — satır başına bir
JSON nesnesi. Sadece `type == "assistant"` ve `message.usage` içeren satırlar
sayılır. İlgilenilen alanlar (yapı JSONL üzerinde doğrulandı):

| Alan | Kullanım |
|---|---|
| `timestamp` (üst düzey, ISO8601) | Gün/ay bucketleme (yerel saat) |
| `cwd` (üst düzey) | Proje atfı — gerçek yol; dizin adını decode etmekten temiz |
| `requestId` (üst düzey) | Dedup anahtarının parçası |
| `message.id` | Dedup anahtarının parçası |
| `message.model` | Fiyat tablosu eşlemesi (ör. `claude-opus-4-8`) |
| `message.usage.input_tokens` | Maliyet + token |
| `message.usage.output_tokens` | Maliyet + token |
| `message.usage.cache_creation_input_tokens` | Cache-write maliyeti |
| `message.usage.cache_read_input_tokens` | Cache-read maliyeti + verimlilik |

**Dedup:** Resume edilen oturumlar ve çoklu JSONL dosyaları aynı assistant
mesajını tekrarlayabilir. Tekilleştirme anahtarı `(message.id, requestId)` —
ccusage ile aynı yaklaşım. Her mesaj yalnızca bir kez sayılır.

## Mimari

Yeni dosyalar (mevcut kod tabanının tek-sorumluluk-per-dosya desenine uyumlu):

| Dosya | Sorumluluk |
|---|---|
| `ClaudeLogParser.swift` | JSONL'i artımlı okur (dosya başına offset+mtime); satırları parse eder; `(id, requestId)` ile tekilleştirir. Saf, test edilebilir; disk erişimi enjekte edilebilir. |
| `TokenPricing.swift` | Gömülü model→fiyat tablosu (input/output/cache-write/cache-read); opsiyonel uzaktan güncelleme. |
| `TokenUsageModel.swift` | Aggregate veri yapıları: `(gün, model, cwd)` kırılımında token & maliyet rollup'ları; aralık/model/proje/cache türetimleri. |
| `TokenUsageService.swift` | `@MainActor ObservableObject`. Parse'ı orkestre eder, aggregate cache'i tutar ve diske yazar, arka planda tazeler. |
| `TokenUsageView.swift` | Popover'daki açılır bölüm UI'ı. |

Mevcut `UsageService` / OAuth koduna **dokunulmaz** — bu bağımsız bir
alt-sistem. Entegrasyon noktaları yalnızca:
`PopoverView` (bölümü yerleştir), `SettingsView` (uzaktan-fiyat toggle'ı),
`ClaudeUsageBarApp` (servisi oluştur/enjekte et).

## Parse Yaklaşımı

**Seçilen:** Artımlı parse + cache'lenmiş aggregate.

- Her dosyanın son okunan byte offset'i + mtime'ı persist edilir:
  `~/.config/claude-usage-bar/token-usage.json` (mevcut history servisiyle aynı
  dizin/desen).
- Tazelemede yalnızca dosyaya **yeni eklenen baytlar** okunur.
- İlk çalıştırmada bir kereye mahsus tam parse; bu sırada UI'da hafif bir
  "hesaplanıyor…" durumu gösterilir.
- Aggregate `(gün, model, cwd)` anahtarında tutulur → Bugün / Bu ay / Tüm
  zamanlar + model kırılımı + proje kırılımı + cache oranı hepsi bundan türer.
- Tazeleme mevcut poll timer'ına bağlanır (ayrı timer yok).
- **Truncate/rotation:** dosya boyu kayıtlı offset'ten küçükse dosya sıfırdan
  okunur.

**Elenen alternatif:** Her popover açılışında arka planda tam parse — daha
basit ama büyük geçmişte ilk boyama yavaş ve her seferinde israf.

## Maliyet Modeli

Model başına, notional $:

```
cost = input · inPrice
     + output · outPrice
     + cacheCreate · cacheWritePrice
     + cacheRead · cacheReadPrice
```

Standart çarpanlar (gömülü tabloda açık sayılarla): cache-write ≈ 1.25× input,
cache-read ≈ 0.1× input. Fiyatlar model id başına saklanır.

- **Gömülü tablo** varsayılandır; ağ/dış bağımlılık gerektirmez (offline çalışır).
- Ayarlardaki **"Fiyatları uzaktan güncelle"** toggle'ı açıksa, fiyatlar uzak
  bir JSON'dan güncellenir (varsayılan kapalı).
- **Bilinmeyen model id** → token yine tam sayılır; o modelin $'ı "?" olarak
  işaretlenir (veri kaybı yok, sadece $ eksik).

## UI

Popover içinde **açılır bölüm**, varsayılan **kapalı** (popover'ı kompakt tutar).

- **Başlık satırı:** `Token & Maliyet` + disclosure chevron + satır içi özet
  (ör. `Bu ay ~$42 · 12M tok`). Kapalıyken tek satır.
- **Açık:** segmented kontrol `Bugün · Bu ay · Tüm zamanlar`
  - Üst: seçili aralık için notional $ + toplam token, "notional" ipucu
  - **Model kırılımı:** Opus / Sonnet / Haiku / Fable satırları — token, $, bar
  - **Proje kırılımı:** maliyete göre ilk N proje (kaydırılabilir liste), bar
  - **Cache verimliliği:** cache-read oranı % + tahmini tasarruf ($ / token)

Popover genişliği 360px olduğundan proje listesi kaydırılabilir bir alanda.

## Ayarlar

- Toggle: **"Fiyatları uzaktan güncelle"** (varsayılan kapalı)
- v1'de tüm projeler dahildir; proje dahil/hariç filtresi sonraki faza.

## Hata Yönetimi

| Durum | Davranış |
|---|---|
| `~/.claude/projects` yok | Bölüm sessizce gizlenir (feature no-op) |
| Bozuk/parse edilemeyen satır | Atlanır, parse devam eder |
| Bilinmeyen model | Token sayılır, $ "?" |
| Cache dosyası bozuk | `.bak`'a taşınır, sıfırdan (history servisiyle aynı desen) |
| Dosya truncate | O dosya offset 0'dan yeniden okunur |
| Zaman dilimi | "bugün / bu ay" **yerel** saatle hesaplanır |

## Test

- **Parser:** dedup `(id, requestId)`, artımlı offset ilerlemesi, truncate/
  rotation, bozuk satır atlama.
- **Aggregation:** gün / model / proje bucketleme; aralık türetimleri
  (bugün / ay / all).
- **Maliyet:** bilinen model doğru hesap; bilinmeyen model "?" ama token sayılır;
  cache-write/read çarpanları.
- **Zaman dilimi:** gün/ay sınırlarında yerel saat davranışı.

## Kapsam Dışı (YAGNI — sonraki fazlar)

- Aktivite ritmi / heatmap / en yoğun saatler
- Burn-rate / tükenme projeksiyonu (Faz 3)
- Menu bar çubuğunda $ veya token gösterimi (Faz 4)
- Geçmiş trend grafiği tüm bucket'lar için (Faz 2)
- Proje dahil/hariç filtresi
- Kota-yüzdesi bucket'larıyla lokal token verisini korelasyon
