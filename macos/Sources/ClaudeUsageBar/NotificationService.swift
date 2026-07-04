import Foundation
@preconcurrency import UserNotifications

struct ThresholdAlert: Equatable {
    let window: String
    let pct: Int
}

/// A scoped limit (e.g. Fable) that has just entered a critical state.
struct CriticalLimitAlert: Equatable {
    let id: String
    let label: String
    let pct: Int?
}

/// Pure logic: which scoped limits have *newly* become critical this poll.
///
/// A limit alerts once when it transitions into `critical` severity and does not
/// re-fire while it stays critical (tracked via `alreadyNotified`). Once a limit
/// drops out of the critical set it is forgotten, so a later re-entry alerts
/// again. Returns the alerts to send plus the set of ids to remember next time.
func newlyCriticalScopedLimits(
    limits: [UsageLimit],
    alreadyNotified: Set<String>
) -> (alerts: [CriticalLimitAlert], criticalNow: Set<String>) {
    let critical = limits.filter { $0.isCritical && ($0.isActive ?? true) }
    let criticalNow = Set(critical.map(\.id))
    let alerts = critical
        .filter { !alreadyNotified.contains($0.id) }
        .map { limit in
            CriticalLimitAlert(
                id: limit.id,
                label: limit.displayLabel,
                pct: limit.percent.map { Int($0.rounded()) }
            )
        }
    return (alerts, criticalNow)
}

/// Pure logic: returns which threshold alerts should fire given a state transition.
func crossedThresholds(
    threshold5h: Int,
    threshold7d: Int,
    thresholdExtra: Int,
    thresholdSonnetOnly: Int = 0,
    thresholdClaudeDesign: Int = 0,
    previous5h: Double,
    previous7d: Double,
    previousExtra: Double,
    previousSonnetOnly: Double = 0.0,
    previousClaudeDesign: Double = 0.0,
    current5h: Double,
    current7d: Double,
    currentExtra: Double,
    currentSonnetOnly: Double = 0.0,
    currentClaudeDesign: Double = 0.0
) -> [ThresholdAlert] {
    var alerts = [ThresholdAlert]()

    if threshold5h > 0 {
        let t = Double(threshold5h)
        if current5h >= t && previous5h < t {
            alerts.append(ThresholdAlert(window: "Current Session", pct: Int(round(current5h))))
        }
    }

    if threshold7d > 0 {
        let t = Double(threshold7d)
        if current7d >= t && previous7d < t {
            alerts.append(ThresholdAlert(window: "All Models", pct: Int(round(current7d))))
        }
    }

    if thresholdExtra > 0 {
        let t = Double(thresholdExtra)
        if currentExtra >= t && previousExtra < t {
            alerts.append(ThresholdAlert(window: "Extra usage", pct: Int(round(currentExtra))))
        }
    }

    if thresholdSonnetOnly > 0 {
        let t = Double(thresholdSonnetOnly)
        if currentSonnetOnly >= t && previousSonnetOnly < t {
            alerts.append(ThresholdAlert(window: "Sonnet Only", pct: Int(round(currentSonnetOnly))))
        }
    }

    if thresholdClaudeDesign > 0 {
        let t = Double(thresholdClaudeDesign)
        if currentClaudeDesign >= t && previousClaudeDesign < t {
            alerts.append(ThresholdAlert(window: "Claude Design", pct: Int(round(currentClaudeDesign))))
        }
    }

    return alerts
}

/// Default lead time (hours) before a weekly reset at which the reminder fires.
let weeklyResetReminderLeadHours: Double = 10

/// Pure logic: whether to fire the "weekly limit resets soon" reminder.
///
/// Fires once when the time remaining until `resetsAt` first drops to within
/// `leadHours`, and not again for that same reset (tracked via
/// `lastNotifiedReset`). Never fires for a reset that has already passed.
func shouldNotifyWeeklyReset(
    resetsAt: Date?,
    now: Date,
    leadHours: Double = weeklyResetReminderLeadHours,
    lastNotifiedReset: Date?
) -> Bool {
    guard let resetsAt else { return false }

    let secondsUntilReset = resetsAt.timeIntervalSince(now)
    guard secondsUntilReset > 0 else { return false }          // already reset / in the past
    guard secondsUntilReset <= leadHours * 3600 else { return false }  // not yet inside the window

    // Same reset already announced — don't repeat on every poll.
    if let lastNotifiedReset,
       abs(lastNotifiedReset.timeIntervalSince(resetsAt)) < 1 {
        return false
    }

    return true
}

private class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

@MainActor
class NotificationService: ObservableObject {
    /// 0 = off, 5–100 = alert when window reaches this %.
    @Published private(set) var threshold5h: Int
    @Published private(set) var threshold7d: Int
    @Published private(set) var thresholdExtra: Int
    @Published private(set) var thresholdSonnetOnly: Int
    @Published private(set) var thresholdClaudeDesign: Int

    /// When enabled, fires a one-shot reminder ~10h before the weekly limit resets.
    @Published private(set) var weeklyResetReminderEnabled: Bool

    /// When enabled, alerts when a model-scoped limit (e.g. Fable) becomes critical.
    /// These live only in the `limits` array and have no dedicated threshold slider.
    @Published private(set) var criticalLimitAlertsEnabled: Bool

    private static let weeklyResetReminderKey = "notificationWeeklyResetReminderEnabled"
    private static let lastNotifiedWeeklyResetKey = "notificationLastNotifiedWeeklyReset"
    private static let criticalLimitAlertsKey = "notificationCriticalLimitAlertsEnabled"

    private var previousPct5h: Double?
    private var previousPct7d: Double?
    private var previousPctExtra: Double?
    private var previousPctSonnetOnly: Double?
    private var previousPctClaudeDesign: Double?
    /// The weekly reset date for which a reminder was last sent (persisted so a
    /// relaunch inside the same window doesn't re-notify).
    private var lastNotifiedWeeklyReset: Date?
    /// Ids of scoped limits currently known to be critical, so we alert on entry
    /// only and not on every subsequent poll.
    private var notifiedCriticalLimits: Set<String> = []
    private let delegate = NotificationDelegate()

    init() {
        threshold5h = Self.load("notificationThreshold5h")
        threshold7d = Self.load("notificationThreshold7d")
        thresholdExtra = Self.load("notificationThresholdExtra")
        thresholdSonnetOnly = Self.load("notificationThresholdSonnetOnly")
        thresholdClaudeDesign = Self.load("notificationThresholdClaudeDesign")

        // Default ON for new users; respect an explicit stored choice otherwise.
        if UserDefaults.standard.object(forKey: Self.weeklyResetReminderKey) == nil {
            weeklyResetReminderEnabled = true
        } else {
            weeklyResetReminderEnabled = UserDefaults.standard.bool(forKey: Self.weeklyResetReminderKey)
        }
        // Default ON for new users; respect an explicit stored choice otherwise.
        if UserDefaults.standard.object(forKey: Self.criticalLimitAlertsKey) == nil {
            criticalLimitAlertsEnabled = true
        } else {
            criticalLimitAlertsEnabled = UserDefaults.standard.bool(forKey: Self.criticalLimitAlertsKey)
        }

        let storedReset = UserDefaults.standard.double(forKey: Self.lastNotifiedWeeklyResetKey)
        lastNotifiedWeeklyReset = storedReset > 0 ? Date(timeIntervalSince1970: storedReset) : nil

        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = delegate
        }
    }

    func setWeeklyResetReminderEnabled(_ value: Bool) {
        weeklyResetReminderEnabled = value
        UserDefaults.standard.set(value, forKey: Self.weeklyResetReminderKey)
        if value { requestPermission() }
    }

    func setCriticalLimitAlertsEnabled(_ value: Bool) {
        criticalLimitAlertsEnabled = value
        UserDefaults.standard.set(value, forKey: Self.criticalLimitAlertsKey)
        if value {
            // Re-enabling should surface anything already critical on the next poll.
            notifiedCriticalLimits = []
            requestPermission()
        }
    }

    func setThreshold5h(_ value: Int) {
        threshold5h = clamp(value)
        UserDefaults.standard.set(threshold5h, forKey: "notificationThreshold5h")
        previousPct5h = nil
        if threshold5h > 0 { requestPermission() }
    }

    func setThreshold7d(_ value: Int) {
        threshold7d = clamp(value)
        UserDefaults.standard.set(threshold7d, forKey: "notificationThreshold7d")
        previousPct7d = nil
        if threshold7d > 0 { requestPermission() }
    }

    func setThresholdExtra(_ value: Int) {
        thresholdExtra = clamp(value)
        UserDefaults.standard.set(thresholdExtra, forKey: "notificationThresholdExtra")
        previousPctExtra = nil
        if thresholdExtra > 0 { requestPermission() }
    }

    func setThresholdSonnetOnly(_ value: Int) {
        thresholdSonnetOnly = clamp(value)
        UserDefaults.standard.set(thresholdSonnetOnly, forKey: "notificationThresholdSonnetOnly")
        previousPctSonnetOnly = nil
        if thresholdSonnetOnly > 0 { requestPermission() }
    }

    func setThresholdClaudeDesign(_ value: Int) {
        thresholdClaudeDesign = clamp(value)
        UserDefaults.standard.set(thresholdClaudeDesign, forKey: "notificationThresholdClaudeDesign")
        previousPctClaudeDesign = nil
        if thresholdClaudeDesign > 0 { requestPermission() }
    }

    func requestPermission() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func checkAndNotify(
        pct5h: Double,
        pct7d: Double,
        pctExtra: Double,
        pctSonnetOnly: Double,
        pctClaudeDesign: Double,
        scopedLimits: [UsageLimit] = [],
        reset7d: Date? = nil,
        now: Date = Date()
    ) {
        checkWeeklyResetReminder(reset7d: reset7d, now: now)
        checkCriticalScopedLimits(scopedLimits)

        let current5h = pct5h * 100
        let current7d = pct7d * 100
        let currentExtra = pctExtra * 100
        let currentSonnetOnly = pctSonnetOnly * 100
        let currentClaudeDesign = pctClaudeDesign * 100

        let prev5h = previousPct5h ?? 0
        let prev7d = previousPct7d ?? 0
        let prevExtra = previousPctExtra ?? 0
        let prevSonnetOnly = previousPctSonnetOnly ?? 0
        let prevClaudeDesign = previousPctClaudeDesign ?? 0

        defer {
            previousPct5h = current5h
            previousPct7d = current7d
            previousPctExtra = currentExtra
            previousPctSonnetOnly = currentSonnetOnly
            previousPctClaudeDesign = currentClaudeDesign
        }

        let alerts = crossedThresholds(
            threshold5h: threshold5h,
            threshold7d: threshold7d,
            thresholdExtra: thresholdExtra,
            thresholdSonnetOnly: thresholdSonnetOnly,
            thresholdClaudeDesign: thresholdClaudeDesign,
            previous5h: prev5h,
            previous7d: prev7d,
            previousExtra: prevExtra,
            previousSonnetOnly: prevSonnetOnly,
            previousClaudeDesign: prevClaudeDesign,
            current5h: current5h,
            current7d: current7d,
            currentExtra: currentExtra,
            currentSonnetOnly: currentSonnetOnly,
            currentClaudeDesign: currentClaudeDesign
        )

        for alert in alerts {
            sendNotification(window: alert.window, pct: alert.pct)
        }
    }

    private func checkCriticalScopedLimits(_ limits: [UsageLimit]) {
        guard criticalLimitAlertsEnabled else { return }

        let (alerts, criticalNow) = newlyCriticalScopedLimits(
            limits: limits,
            alreadyNotified: notifiedCriticalLimits
        )
        notifiedCriticalLimits = criticalNow

        for alert in alerts {
            sendCriticalLimitNotification(id: alert.id, label: alert.label, pct: alert.pct)
        }
    }

    private func checkWeeklyResetReminder(reset7d: Date?, now: Date) {
        guard weeklyResetReminderEnabled else { return }
        guard shouldNotifyWeeklyReset(
            resetsAt: reset7d,
            now: now,
            lastNotifiedReset: lastNotifiedWeeklyReset
        ) else { return }

        guard let reset7d else { return }
        let hoursLeft = max(1, Int(ceil(reset7d.timeIntervalSince(now) / 3600)))
        sendWeeklyResetNotification(hoursLeft: hoursLeft)

        lastNotifiedWeeklyReset = reset7d
        UserDefaults.standard.set(reset7d.timeIntervalSince1970, forKey: Self.lastNotifiedWeeklyResetKey)
    }

    private func sendWeeklyResetNotification(hoursLeft: Int) {
        guard Bundle.main.bundleIdentifier != nil else {
            print("[Notification] Weekly limit resets in ~\(hoursLeft)h (no bundle – skipped)")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Claude Gusage"
        content.body = "Weekly limit resets in about \(hoursLeft) hour\(hoursLeft == 1 ? "" : "s")."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "weekly-reset-reminder",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[Notification] Failed to deliver weekly reset reminder: \(error)")
            } else {
                print("[Notification] Delivered weekly reset reminder (\(hoursLeft)h)")
            }
        }
    }

    private func sendCriticalLimitNotification(id: String, label: String, pct: Int?) {
        let pctSuffix = pct.map { " (\($0)%)" } ?? ""

        guard Bundle.main.bundleIdentifier != nil else {
            print("[Notification] \(label) limit is critical\(pctSuffix) (no bundle – skipped)")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Claude Gusage"
        content.body = "\(label) usage limit is critical\(pctSuffix)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "critical-limit-\(id)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[Notification] Failed to deliver critical limit alert: \(error)")
            } else {
                print("[Notification] Delivered critical limit alert: \(label)\(pctSuffix)")
            }
        }
    }

    private func sendNotification(window: String, pct: Int) {
        guard Bundle.main.bundleIdentifier != nil else {
            print("[Notification] \(window) usage has reached \(pct)% (no bundle – skipped)")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Claude Gusage"
        content.body = "\(window) usage has reached \(pct)%"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "usage-\(window)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[Notification] Failed to deliver: \(error)")
            } else {
                print("[Notification] Delivered: \(window) at \(pct)%")
            }
        }
    }

    private func clamp(_ value: Int) -> Int {
        max(0, min(100, value))
    }

    private static func load(_ key: String) -> Int {
        let value = UserDefaults.standard.integer(forKey: key)
        return max(0, min(100, value))
    }
}
