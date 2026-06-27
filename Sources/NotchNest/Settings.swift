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

    private enum Keys {
        static let meeting = "showMeetingCountdown"
        static let disabledTabs = "disabledTabs"
    }

    private init() {
        showMeetingCountdown = defaults.object(forKey: Keys.meeting) as? Bool ?? true
        disabledTabs = Set(defaults.stringArray(forKey: Keys.disabledTabs) ?? [])
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
}
