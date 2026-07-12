import SwiftUI

@main
struct ClaudeUsageBarApp: App {
    @StateObject private var service = UsageService()
    @StateObject private var historyService = UsageHistoryService()
    @StateObject private var notificationService = NotificationService()
    @StateObject private var appUpdater = AppUpdater()
    @StateObject private var tokenUsageService = TokenUsageService()

    init() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            ClaudeUsageBarApp.clampMenuBarWindow()
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { _ in
            ClaudeUsageBarApp.clampMenuBarWindow()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(
                service: service,
                historyService: historyService,
                notificationService: notificationService,
                appUpdater: appUpdater,
                tokenUsageService: tokenUsageService
            )
        } label: {
            Image(nsImage: service.isAuthenticated
                ? renderIcon(pct5h: service.pct5h, pct7d: service.pct7d)
                : renderUnauthenticatedIcon()
            )
                .task {
                    // Auto-mark existing users as setup-complete
                    if service.isAuthenticated && !UserDefaults.standard.bool(forKey: "setupComplete") {
                        UserDefaults.standard.set(true, forKey: "setupComplete")
                    }
                    historyService.loadHistory()
                    service.historyService = historyService
                    service.notificationService = notificationService
                    service.startPolling()
                    Task { await tokenUsageService.refresh() }
                }
                .onChange(of: service.lastUpdated) { _, _ in
                    Task { await tokenUsageService.refresh() }
                }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsWindowContent(
                service: service,
                notificationService: notificationService
            )
        }
        .windowResizability(.contentSize)
        .windowStyle(.titleBar)
    }

    private static func clampMenuBarWindow() {
        guard let screen = NSScreen.main else { return }
        let maxH = screen.visibleFrame.height - 40

        for window in NSApplication.shared.windows {
            print("DEBUG: Window check - title: '\(window.title)', level: \(window.level.rawValue), styleMask: \(window.styleMask.rawValue)")
            if window.level > .normal {
                window.maxSize = NSSize(width: 360, height: maxH)
                window.minSize = NSSize(width: 360, height: 200)
                if window.frame.height > maxH {
                    var frame = window.frame
                    let diff = frame.height - maxH
                    frame.size.height = maxH
                    frame.origin.y += diff
                    window.setFrame(frame, display: true)
                }
            }
        }
    }
}
