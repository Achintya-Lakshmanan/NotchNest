import SwiftUI
import UniformTypeIdentifiers

/// Preferences: a category rail on the left, one short grouped list on the right.
struct SettingsPane: View {
    @ObservedObject var settings = Settings.shared
    @EnvironmentObject var state: NotchState
    @AppStorage("settingsSection") private var sectionName = Section.general.rawValue
    @State private var draggedTab: NotchTab?
    /// EventKit's calendar list, loaded when the section appears (not on every redraw).
    @State private var calendarList: [CalendarService.CalendarInfo] = []

    enum Section: String, CaseIterable {
        case general = "General"
        case tabs = "Tabs"
        case calendars = "Calendars"
        case notch = "Notch"

        var symbol: String {
            switch self {
            case .general: return "gearshape"
            case .tabs: return "square.grid.2x2"
            case .calendars: return "calendar"
            case .notch: return "rectangle.topthird.inset.filled"
            }
        }
    }

    private var section: Section { Section(rawValue: sectionName) ?? .general }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            rail
            Rectangle().fill(.white.opacity(0.08)).frame(width: 1)
            ScrollView(showsIndicators: false) {
                Group {
                    switch section {
                    case .general: general
                    case .tabs: tabs
                    case .calendars: calendars
                    case .notch: notch
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.vertical, 1)
            }
        }
        .toggleStyle(NotchSwitchStyle())
        .controlSize(.mini)
        .tint(.green)
        .padding(.top, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Rail

    private var rail: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Section.allCases, id: \.self) { item in
                Button { sectionName = item.rawValue } label: {
                    HStack(spacing: 7) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 15)
                        Text(item.rawValue)
                            .font(.system(size: 11.5, weight: .medium))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(section == item ? .white : .white.opacity(0.55))
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(section == item ? .white.opacity(0.13) : .clear,
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(section == item ? .isSelected : [])
            }
            Spacer(minLength: 0)
            Button { NSApp.terminate(nil) } label: {
                HStack(spacing: 7) {
                    Image(systemName: "power").font(.system(size: 10, weight: .semibold)).frame(width: 15)
                    Text("Quit").font(.system(size: 11.5, weight: .medium))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.white.opacity(0.55))
                .padding(.horizontal, 8).padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Quit NotchNest")
            Text("NotchNest 1.0")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.3))
                .padding(.horizontal, 8)
        }
        .frame(width: 122)
    }

    // MARK: Sections

    private var general: some View {
        VStack(alignment: .leading, spacing: 8) {
            card {
                row("Launch at login", isOn: $settings.launchAtLogin)
                line
                row("Class & meeting countdown", isOn: $settings.showMeetingCountdown)
                line
                row("Claude limit alerts", isOn: $settings.claudeLimitAlerts)
                line
                row("Lyrics (from LRCLIB)", isOn: Binding(
                    get: { settings.lyricsEnabled },
                    set: { on in
                        settings.lyricsEnabled = on
                        if !on { state.showingLyrics = false }
                    }))
                line
                row("Next reminder in Calendar", isOn: $settings.showCalendarReminder)
                line
                row(state.focusMonitor.isAvailable ? "Focus and Caps Lock popups" : "Caps Lock popups",
                    isOn: $settings.showSystemPopups)
            }
            if settings.showSystemPopups, state.focusMonitor.isAvailable {
                FocusAccessRow(monitor: state.focusMonitor).padding(.horizontal, 4)
            }
        }
    }

    private var tabs: some View {
        VStack(alignment: .leading, spacing: 8) {
            caption("Tap to show or hide · drag to reorder")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(settings.orderedTabs, id: \.self) { tab in
                    // Not a Button: a button would swallow the mouse-down that starts a drag.
                    chipLabel(tab.title, symbol: tab.symbol, isOn: settings.isEnabled(tab))
                        .onTapGesture { settings.setTab(tab, enabled: !settings.isEnabled(tab)) }
                        .onDrag {
                            draggedTab = tab
                            return NSItemProvider(object: tab.rawValue as NSString)
                        }
                        .onDrop(of: [.text], delegate: TabDropDelegate(target: tab, dragged: $draggedTab,
                                                                       settings: settings))
                        .accessibilityLabel(tab.title)
                        .accessibilityValue(settings.isEnabled(tab) ? "On" : "Off")
                        .accessibilityAddTraits(.isButton)
                }
            }
            caption("Usage tab shows").padding(.top, 2)
            HStack(spacing: 6) {
                chip("Codex", symbol: "terminal", isOn: settings.showCodexUsage) {
                    settings.showCodexUsage.toggle()
                }
                chip("Claude", symbol: "sparkle", isOn: settings.showClaudeUsage) {
                    settings.showClaudeUsage.toggle()
                }
            }
            .frame(width: 190)
        }
    }

    private var calendars: some View {
        let list = calendarList
        return VStack(alignment: .leading, spacing: 8) {
            caption("Used for the grid, class mode and deadlines")
            if !state.calendarAuthorized {
                HStack(spacing: 10) {
                    Text("Choose which calendars NotchNest reads.")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                    Spacer(minLength: 8)
                    Button("Connect Calendar") { state.requestCalendarAccess() }
                        .font(.system(size: 10.5, weight: .semibold))
                        .buttonStyle(.plain)
                        .padding(.horizontal, 11).padding(.vertical, 5)
                        .background(.white.opacity(0.15), in: Capsule())
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else if list.isEmpty {
                Text("No calendars found.")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    .padding(.horizontal, 4)
            } else {
                card {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { line }
                        HStack(spacing: 8) {
                            Circle()
                                .fill(item.colorComponents.count >= 3
                                      ? Color(red: item.colorComponents[0], green: item.colorComponents[1],
                                              blue: item.colorComponents[2]) : .gray)
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(item.title).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.9))
                                    .lineLimit(1)
                                if !item.source.isEmpty {
                                    Text(item.source).font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 8)
                            Toggle(item.title, isOn: Binding(
                                get: { !settings.hiddenCalendars.contains(item.id) },
                                set: { shown in
                                    if shown { settings.hiddenCalendars.remove(item.id) }
                                    else { settings.hiddenCalendars.insert(item.id) }
                                    state.refreshCalendar()
                                }))
                                .labelsHidden()
                        }
                        .padding(.horizontal, 10)
                        .frame(minHeight: 32)
                    }
                }
            }
        }
        .onAppear { calendarList = state.calendar.calendars() }
        .onChange(of: state.calendarAuthorized) { _, _ in calendarList = state.calendar.calendars() }
    }

    private var notch: some View {
        VStack(alignment: .leading, spacing: 8) {
            card {
                row("Show download progress", isOn: $settings.showDownloadsInCompact)
                line
                row("Battery % when closed", isOn: $settings.batteryPercentInCompact)
                line
                row("Battery % when open", isOn: $settings.batteryPercentInExpanded)
            }
            card {
                row("Quiet hours", isOn: $settings.batteryCompactSchedule)
                if settings.batteryCompactSchedule {
                    line
                    HStack(spacing: 6) {
                        Text("From").font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.9))
                        Spacer(minLength: 4)
                        hourPicker($settings.batteryQuietStartHour)
                        Text("to").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                        hourPicker($settings.batteryQuietEndHour)
                    }
                    .padding(.horizontal, 10).frame(height: 28)
                    line
                    row("Also hide music", isOn: $settings.musicCompactRespectQuietHours)
                }
            }
            if settings.batteryCompactSchedule {
                Text("During quiet hours the closed notch hides the battery %.")
                    .font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.4))
                    .padding(.horizontal, 4)
            }
        }
    }

    // MARK: Pieces

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var line: some View {
        Rectangle().fill(.white.opacity(0.07)).frame(height: 1).padding(.leading, 10)
    }

    private func row(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
            Spacer(minLength: 8)
            Toggle(title, isOn: isOn).labelsHidden()
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
    }

    private func caption(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 8.5, weight: .bold)).tracking(0.7)
            .foregroundStyle(.white.opacity(0.4))
            .padding(.horizontal, 2)
    }

    private func chipLabel(_ title: String, symbol: String, isOn: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
            Text(title).font(.system(size: 10.5, weight: .medium)).lineLimit(1)
        }
        .foregroundStyle(isOn ? .white : .white.opacity(0.35))
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .background(isOn ? .white.opacity(0.16) : .white.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
    }

    private func chip(_ title: String, symbol: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { chipLabel(title, symbol: symbol, isOn: isOn) }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
    }

    private func hourPicker(_ selection: Binding<Int>) -> some View {
        Picker("", selection: selection) {
            ForEach(0..<24, id: \.self) { hour in
                Text(Settings.hourLabel(hour)).tag(hour)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .fixedSize()
    }
}

/// The system switch draws grey in a non-key panel, so on and off look alike.
/// This one is always green when on.
struct NotchSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { configuration.isOn.toggle() }
        } label: {
            Capsule()
                .fill(configuration.isOn ? Color.green : Color.white.opacity(0.16))
                .frame(width: 30, height: 18)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                        .padding(2)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

/// Reorders live as the dragged chip passes over another one.
private struct TabDropDelegate: DropDelegate {
    let target: NotchTab
    @Binding var dragged: NotchTab?
    let settings: Settings

    func dropEntered(info: DropInfo) {
        guard let dragged, dragged != target else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            settings.moveTab(dragged, to: target)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragged = nil
        return true
    }
}

private struct FocusAccessRow: View {
    @ObservedObject var monitor: FocusMonitor

    var body: some View {
        if !monitor.isAvailable {
            EmptyView()
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
