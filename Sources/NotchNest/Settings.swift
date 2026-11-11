import SwiftUI

@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()

    private let defaults = UserDefaults.standard

    @Published var launchAtLogin: Bool {
        didSet { LoginItem.set(launchAtLogin) }
    }
    @Published var showMeetingCountdown: Bool {
        didSet { defaults.set(showMeetingCountdown, forKey: Keys.meeting) }
    }
    @Published var disabledTabs: Set<String> {
        didSet { defaults.set(Array(disabledTabs), forKey: Keys.disabledTabs) }
    }
    @Published var batteryPercentInCompact: Bool {
        didSet { defaults.set(batteryPercentInCompact, forKey: Keys.batteryPercentInCompact) }
    }
    @Published var batteryPercentInExpanded: Bool {
        didSet { defaults.set(batteryPercentInExpanded, forKey: Keys.batteryPercentInExpanded) }
    }
    @Published var batteryCompactSchedule: Bool {
        didSet { defaults.set(batteryCompactSchedule, forKey: Keys.batteryCompactSchedule) }
    }
    @Published var batteryQuietStartHour: Int {
        didSet { defaults.set(batteryQuietStartHour, forKey: Keys.batteryQuietStartHour) }
    }
    @Published var batteryQuietEndHour: Int {
        didSet { defaults.set(batteryQuietEndHour, forKey: Keys.batteryQuietEndHour) }
    }
    @Published var musicCompactRespectQuietHours: Bool {
        didSet { defaults.set(musicCompactRespectQuietHours, forKey: Keys.musicCompactRespectQuietHours) }
    }
    @Published var showDownloadsInCompact: Bool {
        didSet { defaults.set(showDownloadsInCompact, forKey: Keys.showDownloadsInCompact) }
    }
    @Published var showCalendarReminder: Bool {
        didSet { defaults.set(showCalendarReminder, forKey: Keys.showCalendarReminder) }
    }
    @Published var showSystemPopups: Bool {
        didSet { defaults.set(showSystemPopups, forKey: Keys.showSystemPopups) }
    }
    /// Saved tab order (raw values). Tabs missing from it keep their default place at the end.
    @Published var tabOrder: [String] {
        didSet { defaults.set(tabOrder, forKey: Keys.tabOrder) }
    }
    /// Providers offered in the usage tab. At least one always stays on.
    @Published var showCodexUsage: Bool {
        didSet {
            defaults.set(showCodexUsage, forKey: Keys.showCodexUsage)
            if !showCodexUsage, !showClaudeUsage { showClaudeUsage = true }
        }
    }
    @Published var showClaudeUsage: Bool {
        didSet {
            defaults.set(showClaudeUsage, forKey: Keys.showClaudeUsage)
            if !showClaudeUsage, !showCodexUsage { showCodexUsage = true }
        }
    }

    private enum Keys {
        static let tabOrder = "tabOrder"
        static let showCodexUsage = "showCodexUsage"
        static let showClaudeUsage = "showClaudeUsage"
        static let meeting = "showMeetingCountdown"
        static let disabledTabs = "disabledTabs"
        static let batteryPercentInCompact = "batteryPercentInCompact"
        static let batteryPercentInExpanded = "batteryPercentInExpanded"
        static let batteryCompactSchedule = "batteryCompactSchedule"
        static let batteryQuietStartHour = "batteryQuietStartHour"
        static let batteryQuietEndHour = "batteryQuietEndHour"
        static let musicCompactRespectQuietHours = "musicCompactRespectQuietHours"
        static let showDownloadsInCompact = "showDownloadsInCompact"
        static let showCalendarReminder = "showCalendarReminder"
        static let showSystemPopups = "showSystemPopups"
    }

    private init() {
        showMeetingCountdown = defaults.object(forKey: Keys.meeting) as? Bool ?? true
        disabledTabs = Set(defaults.stringArray(forKey: Keys.disabledTabs) ?? [])
        batteryPercentInCompact = defaults.object(forKey: Keys.batteryPercentInCompact) as? Bool ?? true
        batteryPercentInExpanded = defaults.object(forKey: Keys.batteryPercentInExpanded) as? Bool ?? true
        batteryCompactSchedule = defaults.object(forKey: Keys.batteryCompactSchedule) as? Bool ?? false
        batteryQuietStartHour = defaults.object(forKey: Keys.batteryQuietStartHour) as? Int ?? 22
        batteryQuietEndHour = defaults.object(forKey: Keys.batteryQuietEndHour) as? Int ?? 8
        musicCompactRespectQuietHours = defaults.object(forKey: Keys.musicCompactRespectQuietHours) as? Bool ?? true
        showDownloadsInCompact = defaults.object(forKey: Keys.showDownloadsInCompact) as? Bool ?? true
        showCalendarReminder = defaults.object(forKey: Keys.showCalendarReminder) as? Bool ?? true
        showSystemPopups = defaults.object(forKey: Keys.showSystemPopups) as? Bool ?? true
        let codex = defaults.object(forKey: Keys.showCodexUsage) as? Bool ?? true
        showCodexUsage = codex
        // Never restore a state with both providers hidden.
        showClaudeUsage = (defaults.object(forKey: Keys.showClaudeUsage) as? Bool ?? true) || !codex
        tabOrder = defaults.stringArray(forKey: Keys.tabOrder) ?? []
        launchAtLogin = LoginItem.isEnabled
    }

    var orderedTabs: [NotchTab] { Self.ordered(tabOrder) }

    var enabledTabs: [NotchTab] {
        orderedTabs.filter { !disabledTabs.contains($0.rawValue) }
    }

    /// Saved order first (ignoring unknown or repeated names), then any tab it doesn't mention.
    nonisolated static func ordered(_ saved: [String]) -> [NotchTab] {
        var result: [NotchTab] = []
        for name in saved {
            if let tab = NotchTab(rawValue: name), !result.contains(tab) { result.append(tab) }
        }
        return result + NotchTab.allCases.filter { !result.contains($0) }
    }

    /// Moves `tab` into the slot currently held by `target`.
    func moveTab(_ tab: NotchTab, to target: NotchTab) {
        var tabs = orderedTabs
        guard tab != target, let from = tabs.firstIndex(of: tab), let to = tabs.firstIndex(of: target) else { return }
        tabs.remove(at: from)
        tabs.insert(tab, at: to)
        tabOrder = tabs.map(\.rawValue)
    }

    var usageProviders: [String] {
        (showCodexUsage ? ["Codex"] : []) + (showClaudeUsage ? ["Claude"] : [])
    }

    func isEnabled(_ tab: NotchTab) -> Bool { !disabledTabs.contains(tab.rawValue) }

    func setTab(_ tab: NotchTab, enabled: Bool) {
        if enabled { disabledTabs.remove(tab.rawValue) }
        else { disabledTabs.insert(tab.rawValue) }
    }

    func isBatteryPercentVisibleInCompact(now: Date = Date(), percent: Int) -> Bool {
        guard percent <= BatteryInfo.compactPercentThreshold else { return false }
        guard batteryPercentInCompact else { return false }
        guard batteryCompactSchedule else { return true }
        return !isQuietHoursActive(now: now)
    }

    func isMusicVisibleInCompact(now: Date = Date()) -> Bool {
        guard musicCompactRespectQuietHours else { return true }
        guard batteryCompactSchedule else { return true }
        return !isQuietHoursActive(now: now)
    }

    func isQuietHoursActive(now: Date = Date()) -> Bool {
        let hour = Calendar.current.component(.hour, from: now)
        return isQuietHour(hour)
    }

    private func isQuietHour(_ hour: Int) -> Bool {
        let start = batteryQuietStartHour
        let end = batteryQuietEndHour
        if start == end { return false }
        if start < end {
            return hour >= start && hour < end
        }
        return hour >= start || hour < end
    }

    private static let hourFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h a"
        return f
    }()

    static func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        let date = Calendar.current.date(from: components) ?? Date()
        return hourFormatter.string(from: date)
    }
}
