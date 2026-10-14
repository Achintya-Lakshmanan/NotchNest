import SwiftUI

struct SettingsPane: View {
    @ObservedObject var settings = Settings.shared
    @EnvironmentObject var state: NotchState

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Preferences")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 8) {
                    wrappingToggle("Launch at login", isOn: $settings.launchAtLogin)
                    wrappingToggle("Show meeting countdown in the notch", isOn: $settings.showMeetingCountdown)
                    wrappingToggle("Show next reminder in Calendar", isOn: $settings.showCalendarReminder)
                    wrappingToggle("Show download icon in closed notch", isOn: $settings.showDownloadsInCompact)
                    wrappingToggle("Show Focus and Caps Lock popups", isOn: $settings.showSystemPopups)
                    if settings.showSystemPopups {
                        FocusAccessRow(monitor: state.focusMonitor)
                    }
                }

                Divider().overlay(.white.opacity(0.08))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Tabs")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                    ForEach(NotchTab.allCases, id: \.self) { tab in
                        HStack(alignment: .center, spacing: 12) {
                            Label(tab.rawValue, systemImage: tab.symbol)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.9))
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Toggle("", isOn: Binding(
                                get: { settings.isEnabled(tab) },
                                set: { settings.setTab(tab, enabled: $0) }
                            ))
                            .labelsHidden()
                        }
                    }
                }

                Divider().overlay(.white.opacity(0.08))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Closed notch")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                    wrappingToggle("Show % in closed notch", isOn: $settings.batteryPercentInCompact)
                    wrappingToggle("Show % in expanded view", isOn: $settings.batteryPercentInExpanded)

                    Text("Quiet hours")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.top, 2)
                    wrappingToggle("Hide closed-notch % during quiet hours", isOn: $settings.batteryCompactSchedule)
                    wrappingToggle("Hide music in closed notch during quiet hours", isOn: $settings.musicCompactRespectQuietHours)
                    if settings.batteryCompactSchedule {
                        HStack(spacing: 10) {
                            Text("From")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.5))
                            Picker("", selection: $settings.batteryQuietStartHour) {
                                ForEach(0..<24, id: \.self) { hour in
                                    Text(Settings.hourLabel(hour)).tag(hour)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            Text("to")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.5))
                            Picker("", selection: $settings.batteryQuietEndHour) {
                                ForEach(0..<24, id: \.self) { hour in
                                    Text(Settings.hourLabel(hour)).tag(hour)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                        if settings.musicCompactRespectQuietHours {
                            Text("Music uses the quiet hours above.")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    } else if settings.musicCompactRespectQuietHours {
                        Text("Enable quiet hours above to hide music on a schedule.")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }

                Divider().overlay(.white.opacity(0.08))

                HStack {
                    Text("NotchNest 1.0")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.35))
                    Spacer()
                    Button("Quit NotchNest") { NSApp.terminate(nil) }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.12), in: Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
        .toggleStyle(.switch)
        .tint(.white.opacity(0.55))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func wrappingToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .labelsHidden()
        }
    }
}

private struct FocusAccessRow: View {
    @ObservedObject var monitor: FocusMonitor

    var body: some View {
        if !monitor.isAvailable {
            Text("Focus popups aren't connected in this build. Caps Lock is ready.")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
        } else {
        switch monitor.authorization {
        case .notDetermined:
            Button("Connect Focus") { monitor.requestAccess() }
                .buttonStyle(.plain).foregroundStyle(.purple)
        case .denied, .restricted:
            Text("Allow Focus status access in System Settings to show Focus popups.")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
        case .authorized:
            Text("Focus popups follow Share Focus Status. macOS may also show its own banner.")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
        @unknown default:
            EmptyView()
        }
        }
    }
}
