import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = Settings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("NotchNest")
                .font(.system(size: 18, weight: .bold))

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                Toggle("Show meeting countdown in the notch", isOn: $settings.showMeetingCountdown)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Tabs").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                ForEach(NotchTab.allCases, id: \.self) { tab in
                    Toggle(isOn: Binding(
                        get: { settings.isEnabled(tab) },
                        set: { settings.setTab(tab, enabled: $0) }
                    )) {
                        Label(tab.rawValue, systemImage: tab.symbol)
                    }
                }
            }

            Divider()

            HStack {
                Text("NotchNest 1.0").font(.system(size: 11)).foregroundStyle(.tertiary)
                Spacer()
                Button("Quit NotchNest") { NSApp.terminate(nil) }
            }
        }
        .toggleStyle(.switch)
        .padding(24)
        .frame(width: 360)
    }
}
