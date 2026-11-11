import SwiftUI

struct AIUsagePane: View {
    @ObservedObject var service: CodexUsageService
    @ObservedObject var claude: ClaudeUsageService
    var liveRefresh = true
    @State private var refreshID = 0
    @AppStorage("allowanceProvider") private var storedProvider = "Codex"
    @ObservedObject private var settings = Settings.shared

    /// The remembered choice, unless that provider is hidden in Preferences.
    private var provider: String {
        let shown = settings.usageProviders
        return shown.contains(storedProvider) ? storedProvider : (shown.first ?? storedProvider)
    }

    private var isClaude: Bool { provider == "Claude" }
    private var usage: WeeklyUsage? { isClaude ? claude.usage : service.usage }
    private var isLoading: Bool { isClaude ? claude.isLoading : service.isLoading }
    private var message: String? { isClaude ? claude.message : service.message }
    private var accent: Color {
        isClaude ? Color(red: 0.94, green: 0.65, blue: 0.49) : Color(red: 0.46, green: 0.95, blue: 0.77)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    if settings.usageProviders.count < 2 {
                        Text(provider)
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 11).padding(.vertical, 5)
                            .background(accent.opacity(0.22), in: Capsule())
                            .padding(3)
                    } else {
                    HStack(spacing: 2) {
                        ForEach(settings.usageProviders, id: \.self) { name in
                            Button { storedProvider = name } label: {
                                Text(name)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(provider == name ? .white : .white.opacity(0.45))
                                    .padding(.horizontal, 11).padding(.vertical, 5)
                                    .background(provider == name ? accent.opacity(0.22) : .clear, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Show \(name) usage")
                            .accessibilityAddTraits(provider == name ? .isSelected : [])
                        }
                    }
                    .padding(3)
                    .background(.white.opacity(0.06), in: Capsule())
                    }
                    if let plan = usage?.planLabel {
                        Text(plan)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(accent.opacity(0.12), in: Capsule())
                            .lineLimit(1)
                            .accessibilityLabel("Subscription tier: \(plan)")
                    }
                    Spacer()
                    if isLoading {
                        ProgressView().controlSize(.mini).scaleEffect(0.7)
                    }
                    if isClaude, usage != nil {
                        Button { claude.connect() } label: {
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                        .disabled(!liveRefresh)
                        .help("Manage Claude connection")
                        .accessibilityLabel("Manage Claude connection")
                    }
                    Button { refreshID += 1 } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold))
                            .frame(width: 25, height: 23)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading || !liveRefresh)
                    .help("Refresh \(provider) usage")
                    .accessibilityLabel("Refresh \(provider) usage")
                }

                if let usage {
                    usageCard(usage, now: context.date)
                    if let session = usage.session {
                        sessionRow(session, now: context.date)
                    }
                    HStack(spacing: 5) {
                        Circle().fill(message == nil ? accent : .orange).frame(width: 4, height: 4)
                        Text(footer(usage, now: context.date))
                            .font(.system(size: 9)).foregroundStyle(.white.opacity(0.45))
                            .lineLimit(2)
                    }
                } else {
                    VStack(spacing: 9) {
                        Image(systemName: isLoading ? "antenna.radiowaves.left.and.right" : (isClaude ? "sparkle" : "terminal"))
                            .font(.system(size: 25, weight: .light)).foregroundStyle(accent)
                        Text(isLoading ? "Checking your weekly allowance…" : "Connect your \(provider) allowance")
                            .font(.system(size: 12, weight: .semibold))
                        Text(message ?? (isClaude ? "Sign in once. Only your plan and usage limits are read."
                                                    : "Uses your existing Codex sign-in. No API key needed."))
                            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                        if isClaude {
                            Button("Connect Claude") { claude.connect() }
                                .font(.system(size: 10, weight: .semibold))
                                .buttonStyle(.plain)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(accent.opacity(0.18), in: Capsule())
                                .foregroundStyle(accent)
                                .disabled(!liveRefresh)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .task(id: "\(provider)-\(refreshID)") {
            guard liveRefresh else { return }
            await refresh(force: refreshID > 0)
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) }
                catch { return }
                await refresh()
            }
        }
    }

    private func refresh(force: Bool = false) async {
        if isClaude { await claude.refresh(force: force) }
        else { await service.refresh(force: force) }
    }

    private func usageCard(_ usage: WeeklyUsage, now: Date) -> some View {
        let expired = usage.resetIsDue(at: now)
        let tint: Color = usage.remainingPercent <= 10 ? .orange : accent
        return HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(expired ? "—" : usage.remainingLabel)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit().foregroundStyle(tint)
                    Text(expired ? "reset due" : "left")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                }
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.10))
                        Capsule().fill(LinearGradient(colors: [tint.opacity(0.6), tint],
                                                     startPoint: .leading, endPoint: .trailing))
                            .frame(width: expired ? 0 : geometry.size.width * usage.remainingPercent / 100)
                    }
                }
                .frame(height: 7)
                Text(expired ? "Waiting for fresh usage" : "of your weekly allowance")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle().fill(.white.opacity(0.09)).frame(width: 1, height: 60)

            VStack(alignment: .leading, spacing: 7) {
                Label("RESETS IN", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 8, weight: .bold)).tracking(0.8)
                    .foregroundStyle(.white.opacity(0.45))
                Text(usage.countdown(at: now))
                    .font(.system(size: 23, weight: .semibold, design: .rounded))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                if let reset = usage.resetsAt {
                    Text(reset.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                        .help(reset.formatted(date: .complete, time: .shortened))
                } else {
                    Text("Not supplied by \(provider)")
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(width: 154, alignment: .leading)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .background(LinearGradient(colors: [accent.opacity(0.12), .white.opacity(0.035)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func sessionRow(_ session: WeeklyUsage.SessionWindow, now: Date) -> some View {
        // A passed reset means the stored reading is stale; the window is full again
        // until the next message starts a new session.
        let expired = session.resetIsDue(at: now)
        let remaining = expired ? 100 : session.remainingPercent
        let tint: Color = remaining <= 10 ? .orange : accent
        let resetText: String = {
            if expired || session.resetsAt == nil { return "Starts with next message" }
            return "Resets in " + WeeklyUsage.countdown(to: session.resetsAt, at: now)
        }()
        return HStack(spacing: 10) {
            Label("5-HOUR", systemImage: "hourglass")
                .font(.system(size: 8, weight: .bold)).tracking(0.8)
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize()
            Text(expired ? "100%" : session.remainingLabel)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit().foregroundStyle(tint)
                .frame(width: 42, alignment: .trailing)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.10))
                    Capsule().fill(tint)
                        .frame(width: geometry.size.width * remaining / 100)
                }
            }
            .frame(height: 5)
            Text(resetText)
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                .monospacedDigit().lineLimit(1)
                .frame(width: 140, alignment: .trailing)
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Five-hour limit: \(expired ? "100%" : session.remainingLabel) left. \(resetText)")
    }

    private func footer(_ usage: WeeklyUsage, now: Date) -> String {
        if message != nil { return "Last known usage · Couldn't refresh. Tap ↻ to retry." }
        if usage.resetIsDue(at: now) { return "Weekly reset reached · checking for the new allowance." }
        let minutes = max(0, Int(now.timeIntervalSince(usage.fetchedAt) / 60))
        return "Account-wide · Updated \(minutes == 0 ? "just now" : "\(minutes)m ago")"
    }
}
