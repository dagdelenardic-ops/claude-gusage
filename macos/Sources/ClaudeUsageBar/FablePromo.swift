import Foundation

/// Launch-window promotion: Fable 5 usage counts at 50% toward plan limits
/// through July 7, 2026.
///
/// This is **informational only**. Anthropic applies the discount server-side,
/// so the `utilization` values returned by the usage API already reflect it.
/// The app never scales any displayed percentage — it just surfaces a reminder
/// banner while the promo is active and hides it automatically afterward.
enum FablePromo {
    /// First instant the promo is no longer active — start of July 8, 2026
    /// in the user's local time zone (so the banner shows through all of Jul 7).
    static let endDate: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = DateComponents(year: 2026, month: 7, day: 8)
        return calendar.date(from: components) ?? .distantPast
    }()

    /// Copy shown in the popover banner. Kept in English to match the rest of the UI.
    static let message = "Fable 5 counts 50% toward limits · through Jul 7"

    static func isActive(now: Date = Date()) -> Bool {
        now < endDate
    }
}
