import SwiftUI

struct PopoverView: View {
    @ObservedObject var service: UsageService
    @ObservedObject var historyService: UsageHistoryService
    @ObservedObject var notificationService: NotificationService
    @ObservedObject var appUpdater: AppUpdater
    @ObservedObject var tokenUsageService: TokenUsageService
    @AppStorage("setupComplete") private var setupComplete = false

    var body: some View {
        Group {
            if !setupComplete && !service.isAuthenticated {
                VStack(alignment: .leading, spacing: 10) {
                    SetupView(
                        service: service,
                        notificationService: notificationService,
                        onComplete: { setupComplete = true }
                    )
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    BrandHeader()
                    if !service.isAuthenticated {
                        signInView
                    } else {
                        usageView
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding()
        .frame(width: 360)
        .tint(Theme.accent)
    }

    @ViewBuilder
    private var signInView: some View {
        if service.isAwaitingCode {
            CodeEntryView(service: service)
        } else {
            Text("Sign in to view your usage.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Sign in with Claude") {
                service.startOAuthFlow()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }

        if let error = service.lastError {
            Label(error, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .font(.caption)
        }

        Divider()
        HStack {
            settingsButton
            Spacer()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private var usageView: some View {
        VStack(alignment: .leading, spacing: 10) {
            if FablePromo.isActive() {
                FablePromoBanner()
            }

            UsageBucketRow(
                label: "Current Session",
                bucket: service.usage?.fiveHour
            )

            Divider()
            Text("Weekly Limits")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            UsageBucketRow(
                label: "All Models",
                bucket: service.usage?.sevenDay
            )

            if let sonnetOnly = service.usage?.sevenDaySonnet {
                UsageBucketRow(
                    label: "Sonnet Only",
                    bucket: sonnetOnly
                )
            }

            if let claudeDesign = service.usage?.claudeDesign {
                UsageBucketRow(
                    label: "Claude Design",
                    bucket: claudeDesign
                )
            }

            if let opus = service.usage?.sevenDayOpus,
               opus.utilization != nil {
                Divider()
                Text("Per-Model (7 day)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                UsageBucketRow(label: "Opus", bucket: opus)
                if let sonnet = service.usage?.sevenDaySonnet {
                    UsageBucketRow(label: "Sonnet", bucket: sonnet)
                }
            }

            if !scopedLimits.isEmpty {
                Divider()
                Text("Model Limits (7 day)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ForEach(scopedLimits) { limit in
                    ScopedLimitRow(limit: limit)
                }
            }

            if let routineRuns = service.usage?.dailyRoutineRuns {
                Divider()
                Text("Additional Features")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                RoutineRunsRow(runs: routineRuns)
            }

            if let extra = service.usage?.extraUsage, extra.isEnabled {
                Divider()
                Text("Usage Credits")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ExtraUsageRow(extra: extra)
            }

            if tokenUsageService.hasData {
                Divider()
                TokenUsageView(service: tokenUsageService)
            }

            Divider()
            UsageChartView(historyService: historyService)

            if let error = service.lastError {
                Divider()
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            if let updaterError = appUpdater.lastError {
                Divider()
                Label(updaterError, systemImage: "arrow.triangle.2.circlepath.circle")
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Divider()

            HStack(spacing: 12) {
                if let updated = service.lastUpdated {
                    Text("Updated \(updated, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 12) {
                settingsButton
                Spacer()
                Button("Refresh") {
                    Task { await service.fetchUsage() }
                }
                .buttonStyle(.borderless)
                .font(.caption)
                if appUpdater.isConfigured {
                    Button("Check for Updates…") {
                        appUpdater.checkForUpdates()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .disabled(!appUpdater.canCheckForUpdates)
                }
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { Task { await tokenUsageService.refresh() } }
    }

    /// Model/surface-scoped limits (e.g. Fable) that have no dedicated bucket.
    private var scopedLimits: [UsageLimit] {
        service.usage?.scopedLimits ?? []
    }

    private var settingsButton: some View {
        SettingsLink {
            Text("Settings…")
        }
        .buttonStyle(.borderless)
        .font(.caption)
    }
}

// MARK: - Brand header

/// "Claude" in ink, "Gusage" in brand red, underlined with a short red rule.
private struct BrandHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Text("Claude")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("Gusage")
                    .font(.headline)
                    .foregroundStyle(Theme.accent)
                Spacer()
            }
            Capsule()
                .fill(Theme.accent)
                .frame(width: 34, height: 2)
        }
    }
}

// MARK: - Setup (first launch)

private struct SetupView: View {
    @ObservedObject var service: UsageService
    @ObservedObject var notificationService: NotificationService
    var onComplete: () -> Void

    var body: some View {
        BrandHeader()
        Text("Configure your preferences to get started.")
            .font(.subheadline)
            .foregroundStyle(.secondary)

        Divider()

        LaunchAtLoginToggle(controlSize: .small, useSwitchStyle: true)

        Divider()

        VStack(alignment: .leading, spacing: 8) {
            Text("Notifications")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            SetupThresholdSlider(
                label: "Current Session",
                value: notificationService.threshold5h,
                onChange: { notificationService.setThreshold5h($0) }
            )
            SetupThresholdSlider(
                label: "All Models",
                value: notificationService.threshold7d,
                onChange: { notificationService.setThreshold7d($0) }
            )
            SetupThresholdSlider(
                label: "Sonnet Only",
                value: notificationService.thresholdSonnetOnly,
                onChange: { notificationService.setThresholdSonnetOnly($0) }
            )
            SetupThresholdSlider(
                label: "Claude Design",
                value: notificationService.thresholdClaudeDesign,
                onChange: { notificationService.setThresholdClaudeDesign($0) }
            )
            SetupThresholdSlider(
                label: "Extra usage",
                value: notificationService.thresholdExtra,
                onChange: { notificationService.setThresholdExtra($0) }
            )
        }

        Divider()

        VStack(alignment: .leading, spacing: 6) {
            Text("Polling Interval")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("", selection: Binding(
                get: { service.pollingMinutes },
                set: { service.updatePollingInterval($0) }
            )) {
                ForEach(UsageService.pollingOptions, id: \.self) { mins in
                    Text(localizedPollingInterval(for: mins, locale: .autoupdatingCurrent))
                        .tag(mins)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if isDiscouragedPollingOption(service.pollingMinutes) {
                Text("Frequent polling may cause rate limiting")
                    .font(.caption2)
                    .foregroundStyle(Theme.accent)
            }
        }

        Divider()

        Button("Get Started") {
            onComplete()
        }
        .buttonStyle(.borderedProminent)
        .frame(maxWidth: .infinity)

        HStack {
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Subviews

private struct CodeEntryView: View {
    @ObservedObject var service: UsageService
    @State private var code = ""

    var body: some View {
        Text("Paste the code from your browser:")
            .font(.subheadline)
            .foregroundStyle(.secondary)

        HStack(spacing: 4) {
            TextField("code#state", text: $code)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onSubmit { submit() }
            Button {
                if let str = NSPasteboard.general.string(forType: .string) {
                    code = str.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } label: {
                Image(systemName: "doc.on.clipboard")
            }
            .buttonStyle(.borderless)
        }

        HStack {
            Button("Cancel") {
                service.isAwaitingCode = false
            }
            .buttonStyle(.borderless)
            Spacer()
            Button("Submit") { submit() }
                .buttonStyle(.borderedProminent)
                .disabled(code.isEmpty)
        }
    }

    private func submit() {
        let value = code
        Task { await service.submitOAuthCode(value) }
    }
}

private struct FablePromoBanner: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "sparkles")
                .foregroundStyle(Theme.accent)
            Text(FablePromo.message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.accentSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Theme.accent.opacity(0.25), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct ScopedLimitRow: View {
    let limit: UsageLimit

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(limit.displayLabel)
                    .font(.subheadline)
                if limit.isCritical {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
                Spacer()
                Text(limit.percentText)
                    .font(.subheadline)
                    .monospacedDigit()
            }
            ProgressView(value: min((limit.percent ?? 0) / 100.0, 1.0), total: 1.0)
                .tint(tint)
            if let resetDate = limit.resetsAtDate {
                Text("Resets \(resetDate, style: .relative)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Honor the server's own severity when present; otherwise fall back to percent.
    private var tint: Color {
        switch limit.severity?.lowercased() {
        case "critical": return Theme.accent
        case "warning", "warn": return Theme.accent.opacity(0.70)
        default: return colorForPct((limit.percent ?? 0) / 100.0)
        }
    }
}

private struct UsageBucketRow: View {
    let label: String
    let bucket: UsageBucket?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.subheadline)
                Spacer()
                Text(percentageText)
                    .font(.subheadline)
                    .monospacedDigit()
            }
            ProgressView(value: (bucket?.utilization ?? 0) / 100.0, total: 1.0)
                .tint(colorForPct((bucket?.utilization ?? 0) / 100.0))
            if let resetDate = bucket?.resetsAtDate {
                Text("Resets \(resetDate, style: .relative)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var percentageText: String {
        guard let pct = bucket?.utilization else { return "—" }
        return "\(Int(round(pct)))%"
    }
}

private struct ExtraUsageRow: View {
    let extra: ExtraUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let used = extra.usedCreditsAmount, let limit = extra.monthlyLimitAmount {
                    Text("\(ExtraUsage.formatUSD(used)) / \(ExtraUsage.formatUSD(limit))")
                        .font(.subheadline)
                        .monospacedDigit()
                } else {
                    Text("Usage Credits")
                        .font(.subheadline)
                }
                Spacer()
                if let pct = extra.utilization {
                    Text("\(Int(round(pct)))%")
                        .font(.subheadline)
                        .monospacedDigit()
                }
            }
            ProgressView(value: (extra.utilization ?? 0) / 100.0, total: 1.0)
                .tint(Theme.usageColor((extra.utilization ?? 0) / 100.0))
        }
    }
}

private struct RoutineRunsRow: View {
    let runs: RoutineRunsBucket

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Daily Routine Runs")
                    .font(.subheadline)
                Spacer()
                if let used = runs.used, let total = runs.total {
                    Text("\(used) / \(total)")
                        .font(.subheadline)
                        .monospacedDigit()
                }
            }
            if let utilization = runs.utilization {
                ProgressView(value: utilization / 100.0, total: 1.0)
                    .tint(colorForPct(utilization / 100.0))
            }
            if let resetDate = runs.resetsAtDate {
                Text("Resets \(resetDate, style: .relative)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SetupThresholdSlider: View {
    let label: String
    let value: Int
    let onChange: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.callout)
                Spacer()
                Text(value > 0 ? "\(value)%" : "Off")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { onChange(Int($0)) }
                ),
                in: 0...100,
                step: 5
            )
            .controlSize(.small)
        }
    }
}

private func colorForPct(_ pct: Double) -> Color {
    Theme.usageColor(pct)
}
