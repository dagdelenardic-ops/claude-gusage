import SwiftUI

/// Claude Gusage visual identity: **Black · White · Red**.
///
/// A neutral monochrome base (system `.primary`/`.secondary`, which adapt to
/// light and dark automatically) with red accents — the "kırmızı dokunuşlar".
enum Theme {
    /// Primary brand red — the active tint, header accent, and critical state.
    static let accent = Color(red: 0.84, green: 0.13, blue: 0.16)

    /// A deeper red for emphasis / pressed moments.
    static let accentStrong = Color(red: 0.68, green: 0.09, blue: 0.12)

    /// Soft red wash for banners and subtle highlights.
    static let accentSoft = accent.opacity(0.10)

    /// Neutral ink for low-usage bars and the secondary chart series.
    static let neutral = Color.primary.opacity(0.55)

    /// Slightly stronger neutral for chart lines that need to stay legible.
    static let ink = Color.primary.opacity(0.72)

    /// Progress tint: neutral while low, warming into red as usage climbs.
    static func usageColor(_ pct: Double) -> Color {
        switch pct {
        case ..<0.60: return neutral
        case 0.60..<0.85: return accent.opacity(0.70)
        default: return accent
        }
    }
}
