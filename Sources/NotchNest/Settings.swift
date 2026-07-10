import SwiftUI

extension Notification.Name {
    static let openPreferences = Notification.Name("NotchNestOpenPreferences")
}

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

    private enum Keys {
        static let meeting = "showMeetingCountdown"
        static let disabledTabs = "disabledTabs"
        static let batteryPercentInCompact = "batteryPercentInCompact"
        static let batteryPercentInExpanded = "batteryPercentInExpanded"
        static let batteryCompactSchedule = "batteryCompactSchedule"
        static let batteryQuietStartHour = "batteryQuietStartHour"
        static let batteryQuietEndHour = "batteryQuietEndHour"
    }

    private init() {
        showMeetingCountdown = defaults.object(forKey: Keys.meeting) as? Bool ?? true
        disabledTabs = Set(defaults.stringArray(forKey: Keys.disabledTabs) ?? [])
        batteryPercentInCompact = defaults.object(forKey: Keys.batteryPercentInCompact) as? Bool ?? true
        batteryPercentInExpanded = defaults.object(forKey: Keys.batteryPercentInExpanded) as? Bool ?? true
        batteryCompactSchedule = defaults.object(forKey: Keys.batteryCompactSchedule) as? Bool ?? false
        batteryQuietStartHour = defaults.object(forKey: Keys.batteryQuietStartHour) as? Int ?? 22
        batteryQuietEndHour = defaults.object(forKey: Keys.batteryQuietEndHour) as? Int ?? 8
        launchAtLogin = LoginItem.isEnabled
    }

    var enabledTabs: [NotchTab] {
        NotchTab.allCases.filter { !disabledTabs.contains($0.rawValue) }
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
        let hour = Calendar.current.component(.hour, from: now)
        return !isQuietHour(hour)
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

    static func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        let date = Calendar.current.date(from: components) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        return formatter.string(from: date)
    }
}
