import SwiftUI
import AppKit

/// Renders the UI to PNGs (set NOTCHNEST_SNAPSHOT_DIR) for visual verification,
/// then quits. Not part of normal operation.
@MainActor
enum Snapshot {
    static func runIfRequested() -> Bool {
        guard let dir = ProcessInfo.processInfo.environment["NOTCHNEST_SNAPSHOT_DIR"] else { return false }
        let base = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        let metrics = NotchMetrics(notchWidth: 200, notchHeight: 37, screenFrame: .zero)
        if ProcessInfo.processInfo.environment["NOTCHNEST_SNAPSHOT_REMINDERS_ONLY"] == "1" {
            renderReminders(metrics: metrics, base: base)
            return true
        }
        if ProcessInfo.processInfo.environment["NOTCHNEST_SNAPSHOT_CODEX_ONLY"] == "1" {
            renderCodex(metrics: metrics, base: base)
            return true
        }

        // Expanded music with fictional metadata and generated cover artwork.
        let s1 = NotchState(metrics: metrics)
        s1.isExpanded = true
        s1.tab = .music
        s1.nowPlaying = NowPlaying(app: .music, title: "After Hours", artist: "Night Drive",
                                   album: "Blue Hour", isPlaying: true,
                                   elapsed: 96, duration: 244, artworkURL: nil, isFavorited: true)
        s1.battery = BatteryInfo(level: 0.62, isCharging: true, isPluggedIn: true, hasBattery: true)
        s1.artwork = sampleArtwork()
        s1.artworkColor = Color(red: 0.33, green: 0.40, blue: 0.85)
        render(s1, size: metrics.expandedSize, to: base.appendingPathComponent("1_music_charging.png"))

        // 2. Expanded — calendar month view with events
        let s2 = NotchState(metrics: metrics)
        s2.disableLiveRefresh = true
        s2.isExpanded = true
        s2.tab = .calendar
        s2.calendarAuthorized = true
        let now = Date()
        s2.monthEvents = [
            CalEvent(id: "a", title: "Standup", start: now.addingTimeInterval(-1800),
                     end: now.addingTimeInterval(900), isAllDay: false, colorComponents: [0.2, 0.6, 1, 1]),
            CalEvent(id: "b", title: "Project review", start: now.addingTimeInterval(3600),
                     end: now.addingTimeInterval(7200), isAllDay: false, colorComponents: [1, 0.4, 0.3, 1]),
            CalEvent(id: "c", title: "Gym", start: now.addingTimeInterval(18000),
                     end: now.addingTimeInterval(21600), isAllDay: false, colorComponents: [0.4, 0.8, 0.4, 1]),
        ]
        s2.battery = BatteryInfo(level: 0.85, isCharging: false, isPluggedIn: false, hasBattery: true)
        render(s2, size: metrics.expandedSize, to: base.appendingPathComponent("2_calendar.png"))

        // 3. Expanded — shelf with files
        let s3 = NotchState(metrics: metrics)
        s3.isExpanded = true
        s3.tab = .shelf
        s3.shelf = [
            ShelfItem(url: URL(fileURLWithPath: "/System/Applications/Music.app")),
            ShelfItem(url: URL(fileURLWithPath: "/System/Applications/Notes.app")),
            ShelfItem(url: URL(fileURLWithPath: "/System/Applications/Calendar.app")),
        ]
        s3.battery = BatteryInfo(level: 0.5, isCharging: false, isPluggedIn: false, hasBattery: true)
        render(s3, size: metrics.expandedSize, to: base.appendingPathComponent("3_shelf.png"))

        // 4. Bluetooth connect toast (small banner)
        let s4 = NotchState(metrics: metrics)
        s4.btPopup = BTToast(device: BTDevice(address: "x", name: "AirPods Pro",
                                              batteryMain: nil, batteryLeft: 97, batteryRight: 97,
                                              batteryCase: 82, minorType: "Headphones"),
                             kind: .connected)
        s4.battery = BatteryInfo(level: 0.62, isCharging: true, isPluggedIn: true, hasBattery: true)
        render(s4, size: metrics.toastSize, to: base.appendingPathComponent("4_bt_popup.png"))

        // 6 & 7. Disconnect + low-battery toasts
        let airpods = BTDevice(address: "x", name: "AirPods Pro",
                               batteryMain: nil, batteryLeft: 18, batteryRight: 20,
                               batteryCase: 60, minorType: "Headphones")
        let s6 = NotchState(metrics: metrics)
        s6.btPopup = BTToast(device: airpods, kind: .disconnected)
        s6.battery = BatteryInfo(level: 0.62, isCharging: false, isPluggedIn: false, hasBattery: true)
        render(s6, size: metrics.toastSize, to: base.appendingPathComponent("6_bt_disconnect.png"))

        let s7 = NotchState(metrics: metrics)
        s7.btPopup = BTToast(device: airpods, kind: .lowBattery)
        s7.battery = BatteryInfo(level: 0.62, isCharging: false, isPluggedIn: false, hasBattery: true)
        render(s7, size: metrics.toastSize, to: base.appendingPathComponent("7_bt_low.png"))

        let focus = NotchState(metrics: metrics)
        focus.alert = AlertToast(symbol: "moon.fill", title: "Focus On",
                                 subtitle: "Notifications silenced", tint: .purple)
        render(focus, size: metrics.toastSize, to: base.appendingPathComponent("focus_popup.png"))
        let caps = NotchState(metrics: metrics)
        caps.alert = AlertToast(symbol: "capslock.fill", title: "Caps Lock On",
                                subtitle: "Typing in uppercase", tint: .orange)
        render(caps, size: metrics.toastSize, to: base.appendingPathComponent("caps_lock_popup.png"))

        // 8. Weather
        let s8 = NotchState(metrics: metrics)
        s8.isExpanded = true
        s8.tab = .weather
        s8.weather = WeatherInfo(temp: 72, high: 78, low: 61, unit: "°F",
                                 code: 1, isDay: true, city: "State College",
                                 hourly: [
                                    HourForecast(id: "0", label: "Now", temp: 72, code: 1, isDay: true, precip: 0),
                                    HourForecast(id: "1", label: "3 PM", temp: 74, code: 2, isDay: true, precip: 10),
                                    HourForecast(id: "2", label: "4 PM", temp: 73, code: 61, isDay: true, precip: 55),
                                    HourForecast(id: "3", label: "5 PM", temp: 70, code: 95, isDay: true, precip: 80),
                                    HourForecast(id: "4", label: "6 PM", temp: 67, code: 80, isDay: true, precip: 40),
                                    HourForecast(id: "5", label: "7 PM", temp: 64, code: 3, isDay: false, precip: 20),
                                    HourForecast(id: "6", label: "8 PM", temp: 62, code: 0, isDay: false, precip: 0),
                                 ])
        s8.battery = BatteryInfo(level: 0.8, isCharging: false, isPluggedIn: false, hasBattery: true)
        render(s8, size: metrics.expandedSize, to: base.appendingPathComponent("8_weather.png"))

        // 9. Volume HUD
        let s9 = NotchState(metrics: metrics)
        s9.hud = HUDInfo(kind: .volume, value: 0.6)
        render(s9, size: metrics.hudSize, to: base.appendingPathComponent("9_hud_volume.png"))

        // 10. Brightness HUD
        let s10 = NotchState(metrics: metrics)
        s10.hud = HUDInfo(kind: .brightness, value: 0.75)
        render(s10, size: metrics.hudSize, to: base.appendingPathComponent("10_hud_brightness.png"))

        // 11. Rain alert toast
        let s11 = NotchState(metrics: metrics)
        s11.alert = AlertToast(symbol: "cloud.rain.fill", title: "Rain Likely Soon",
                               subtitle: "Showers expected within a few hours",
                               tint: Color(red: 0.5, green: 0.8, blue: 1.0))
        render(s11, size: metrics.toastSize, to: base.appendingPathComponent("11_rain_alert.png"))

        // 12. Timer running
        let s12 = NotchState(metrics: metrics)
        s12.isExpanded = true
        s12.tab = .timer
        s12.timerDuration = 25 * 60
        s12.timerRemaining = 15 * 60
        s12.timerRunning = true
        render(s12, size: metrics.expandedSize, to: base.appendingPathComponent("12_timer.png"))

        // Timer idle (Start + stepper) and a Pomodoro break.
        let idle = NotchState(metrics: metrics)
        idle.isExpanded = true
        idle.tab = .timer
        idle.timerDuration = 25 * 60
        idle.timerRemaining = 25 * 60
        render(idle, size: metrics.expandedSize, to: base.appendingPathComponent("12_timer_idle.png"))
        let rest = NotchState(metrics: metrics)
        rest.isExpanded = true
        rest.tab = .timer
        rest.setPomodoroForPreview(PomodoroState(phase: .rest, round: 2))
        rest.timerDuration = 5 * 60
        rest.timerRemaining = 3 * 60 + 12
        rest.timerRunning = true
        render(rest, size: metrics.expandedSize, to: base.appendingPathComponent("12_timer_break.png"))

        // 5. Compact — playing + charging
        let s5 = NotchState(metrics: metrics)
        s5.nowPlaying = s1.nowPlaying
        s5.artwork = s1.artwork
        s5.artworkColor = s1.artworkColor
        s5.battery = BatteryInfo(level: 0.62, isCharging: true, isPluggedIn: true, hasBattery: true)
        render(s5, size: metrics.compactSize, to: base.appendingPathComponent("5_compact_charging.png"))

        renderCodex(metrics: metrics, base: base)
        renderReminders(metrics: metrics, base: base)
        renderSettings(metrics: metrics, base: base)
        renderFeatures(metrics: metrics, base: base, music: s1)
        let drawer = NotchState(metrics: metrics, menuBarApps: MenuBarAppsService(preview:
            ["Music", "Calendar", "Notes", "Safari", "Reminders", "Shortcuts"].enumerated().map { index, name in
                MenuBarAppItem(id: "sample-\(index)", appName: name, label: name,
                    icon: NSWorkspace.shared.icon(forFile: ["/System/Applications/\(name).app",
                                                            "/System/Cryptexes/App/System/Applications/\(name).app",
                                                            "/Applications/\(name).app"]
                        .first { FileManager.default.fileExists(atPath: $0) } ?? "/System/Applications/\(name).app"),
                    visibility: index == 0 ? .covered : .visible, frame: nil, element: nil, pid: 0)
            }))
        drawer.isExpanded = true
        drawer.showingMenuBarApps = true
        render(drawer, size: metrics.expandedSize, to: base.appendingPathComponent("menu_bar_apps.png"))
        return true
    }

    /// Class mode, deadlines, lyrics and Claude alerts (fictional fixtures).
    private static func renderFeatures(metrics: NotchMetrics, base: URL, music: NotchState) {
        let now = Date()
        let lyrics = NotchState(metrics: metrics)
        lyrics.disableLiveRefresh = true
        lyrics.isExpanded = true
        lyrics.tab = .music
        lyrics.nowPlaying = music.nowPlaying
        lyrics.artwork = music.artwork
        lyrics.artworkColor = music.artworkColor
        lyrics.showingLyrics = true
        lyrics.setLyricsForPreview(.synced([
            LyricLine(time: 80, text: "Streetlights hum a quiet tune"),
            LyricLine(time: 92, text: "We drive until the blue hour fades"),
            LyricLine(time: 101, text: "And the city wakes without us"),
        ]))
        render(lyrics, size: metrics.expandedSize, to: base.appendingPathComponent("music_lyrics.png"))

        let cal = Calendar.current
        let midnight = cal.startOfDay(for: now)
        func day(_ n: Int, _ hour: Double = 0) -> Date {
            cal.date(byAdding: .day, value: n, to: midnight)!.addingTimeInterval(hour * 3600)
        }
        let deadlines = Deadline.from([
            CalEvent(id: "d1", title: "Problem Set 4 due", start: now.addingTimeInterval(5 * 3600),
                     end: now.addingTimeInterval(5 * 3600), isAllDay: false, colorComponents: [0.3, 0.65, 1, 1]),
            CalEvent(id: "d2", title: "Late Drop - Deadline until 11:59 p.m. (ET)*", start: day(2), end: day(2, 1),
                     isAllDay: false, colorComponents: [0.6, 0.5, 1, 1]),
            CalEvent(id: "d3", title: "Midterm Exam 2", start: day(6, 18.25), end: day(6, 19.5),
                     isAllDay: false, colorComponents: [1, 0.55, 0.35, 1]),
        ], now: now)
        let lecture = CalEvent(id: "lec", title: "Systems Seminar", start: now.addingTimeInterval(-38 * 60),
                               end: now.addingTimeInterval(12 * 60), isAllDay: false,
                               colorComponents: [0.3, 0.65, 1, 1], location: "Willard Building 062")
        let next = CalEvent(id: "next", title: "Algorithms - LEC", start: now.addingTimeInterval(52 * 60),
                            end: now.addingTimeInterval(102 * 60), isAllDay: false,
                            colorComponents: [1, 0.6, 0.4, 1], location: "Thomas Building 100")

        for (name, showing) in [("calendar_deadline_badge", false), ("calendar_deadlines", true)] {
            let state = NotchState(metrics: metrics)
            state.disableLiveRefresh = true
            state.isExpanded = true
            state.tab = .calendar
            state.calendarAuthorized = true
            state.monthEvents = [lecture, next]
            state.deadlines = deadlines
            state.showingDeadlines = showing
            render(state, size: metrics.expandedSize, to: base.appendingPathComponent("\(name).png"))
        }

        for (name, event) in [("compact_class_live", lecture), ("compact_class_upcoming", next)] {
            let state = NotchState(metrics: metrics)
            state.disableLiveRefresh = true
            state.todayEvents = [event]
            render(state, size: metrics.compactSize, to: base.appendingPathComponent("\(name).png"))
        }

        let headsUp = NotchState(metrics: metrics)
        headsUp.alert = AlertToast(symbol: "graduationcap.fill", title: next.title,
                                   subtitle: "Starts in 10 min · Thomas Building 100", tint: next.color)
        render(headsUp, size: metrics.toastSize, to: base.appendingPathComponent("class_heads_up.png"))

        let claude = NotchState(metrics: metrics)
        claude.disableLiveRefresh = true
        claude.checkClaudeAlerts(WeeklyUsage(usedPercent: 30, resetsAt: now.addingTimeInterval(3 * 86400), fetchedAt: now,
                                             session: .init(usedPercent: 93, resetsAt: now.addingTimeInterval(4740))), now: now)
        render(claude, size: metrics.toastSize, to: base.appendingPathComponent("claude_low_alert.png"))
    }

    private static func renderSettings(metrics: NotchMetrics, base: URL) {
        let original = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        defer { UserDefaults.standard.setVolatileDomain(original, forName: UserDefaults.argumentDomain) }
        for section in SettingsPane.Section.allCases {
            var arguments = original
            arguments["settingsSection"] = section.rawValue
            UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
            let state = NotchState(metrics: metrics)
            state.disableLiveRefresh = true
            state.isExpanded = true
            state.showingPreferences = true
            let name = section.rawValue.lowercased().replacingOccurrences(of: " ", with: "_")
            render(state, size: metrics.expandedSize, to: base.appendingPathComponent("settings_\(name).png"))
        }
    }

    private static func renderCodex(metrics: NotchMetrics, base: URL) {
        // Fixture only; these snapshots never query the account or other apps.
        let originalArguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        var arguments = originalArguments
        arguments["allowanceProvider"] = "Codex"
        UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        // Both providers on for these fixtures, restored afterwards.
        let settings = Settings.shared
        let (codexWasShown, claudeWasShown) = (settings.showCodexUsage, settings.showClaudeUsage)
        settings.showCodexUsage = true
        settings.showClaudeUsage = true
        defer {
            UserDefaults.standard.setVolatileDomain(originalArguments, forName: UserDefaults.argumentDomain)
            settings.showClaudeUsage = claudeWasShown
            settings.showCodexUsage = codexWasShown
        }
        let codex = CodexUsageService(usage: WeeklyUsage(
            usedPercent: 45, resetsAt: Date().addingTimeInterval(93720), fetchedAt: Date(), planType: "pro",
            session: .init(usedPercent: 20, resetsAt: Date().addingTimeInterval(11400))))
        let s13 = NotchState(metrics: metrics, codexUsage: codex)
        s13.disableLiveRefresh = true
        s13.isExpanded = true
        s13.tab = .codex
        s13.battery = BatteryInfo(level: 0.62, isCharging: true, isPluggedIn: true,
                                 timeToFullChargeMinutes: 90)
        s13.btDevices = [BTDevice(address: "fixture", name: "AirPods Pro", batteryMain: nil,
                                  batteryLeft: 97, batteryRight: 97, batteryCase: 82, minorType: "Headphones")]
        render(s13, size: metrics.expandedSize, to: base.appendingPathComponent("13_codex.png"))

        let s14 = NotchState(metrics: metrics, codexUsage: CodexUsageService(usage: WeeklyUsage(
            usedPercent: 96, resetsAt: Date().addingTimeInterval(2400), fetchedAt: Date())))
        s14.disableLiveRefresh = true
        s14.isExpanded = true
        s14.tab = .codex
        render(s14, size: metrics.expandedSize, to: base.appendingPathComponent("14_codex_low.png"))

        let s15 = NotchState(metrics: metrics, codexUsage: CodexUsageService(usage: WeeklyUsage(
            usedPercent: 96, resetsAt: Date().addingTimeInterval(-60), fetchedAt: Date().addingTimeInterval(-600))))
        s15.disableLiveRefresh = true
        s15.isExpanded = true
        s15.tab = .codex
        render(s15, size: metrics.expandedSize, to: base.appendingPathComponent("15_codex_reset_due.png"))
        arguments["allowanceProvider"] = "Claude"
        UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        let claude = NotchState(metrics: metrics, claudeUsage: ClaudeUsageService(usage: WeeklyUsage(
            usedPercent: 32.5, resetsAt: Date().addingTimeInterval(196200), fetchedAt: Date(), planType: "max",
            session: .init(usedPercent: 58, resetsAt: Date().addingTimeInterval(8040)))))
        claude.disableLiveRefresh = true
        claude.isExpanded = true
        claude.tab = .codex
        render(claude, size: metrics.expandedSize, to: base.appendingPathComponent("claude.png"))
        let connect = NotchState(metrics: metrics)
        connect.disableLiveRefresh = true
        connect.isExpanded = true
        connect.tab = .codex
        render(connect, size: metrics.expandedSize, to: base.appendingPathComponent("claude_connect.png"))

        // Codex not signed in / unavailable (the provider choice must be Codex again).
        arguments["allowanceProvider"] = "Codex"
        UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        let s16 = NotchState(metrics: metrics)
        s16.disableLiveRefresh = true
        s16.isExpanded = true
        s16.tab = .codex
        render(s16, size: metrics.expandedSize, to: base.appendingPathComponent("16_codex_unavailable.png"))
    }

    private static func render(_ state: NotchState, size: CGSize, to url: URL) {
        state.disableLiveRefresh = true
        let content = ZStack {
            // Stand-in wallpaper so we can see the card edges / transparency.
            LinearGradient(colors: [Color(white: 0.30), Color(white: 0.18)],
                           startPoint: .top, endPoint: .bottom)
            NotchRootView(state: state).environmentObject(state)
        }
        .frame(width: size.width, height: size.height)

        // AppKit renders scroll views and native controls that ImageRenderer omits.
        // This is an offscreen view, not a capture of the user's desktop.
        let host = NSHostingView(rootView: content)
        host.sizingOptions = []
        host.frame = CGRect(origin: .zero, size: size)
        // Give text and SF Symbols a real backing scale without showing a window.
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }

    private static func sampleArtwork() -> NSImage? {
        let cover = ZStack {
            LinearGradient(colors: [Color(red: 0.12, green: 0.16, blue: 0.42), .black],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(LinearGradient(colors: [.cyan, .indigo], startPoint: .top, endPoint: .bottom))
                .frame(width: 175, height: 175)
                .offset(x: 40, y: -25)
            VStack(alignment: .leading, spacing: 3) {
                Spacer()
                Text("NIGHT DRIVE").font(.system(size: 10, weight: .medium)).tracking(3)
                Text("BLUE HOUR").font(.system(size: 26, weight: .black)).tracking(-1)
            }
            .foregroundStyle(.white)
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 256, height: 256)
        .clipped()
        let renderer = ImageRenderer(content: cover)
        renderer.scale = 2
        return renderer.nsImage
    }

    private static func renderReminders(metrics: NotchMetrics, base: URL) {
        let now = Date()
        let upcoming = ReminderInfo(id: "preview", title: "Send the project update", listName: "Personal",
                                    due: now.addingTimeInterval(2400), dateOnly: false, colorComponents: [0.7, 0.6, 1])
        let overdue = ReminderInfo(id: "preview-old", title: "Return library books", listName: "Errands",
                                   due: now.addingTimeInterval(-3600), dateOnly: false, colorComponents: [1, 0.65, 0.3])
        let cases: [(String, ReminderCardState)] = [
            ("17_calendar_reminder", .ready(upcoming)), ("18_calendar_reminder_overdue", .ready(overdue)),
            ("19_calendar_reminder_connect", .connect), ("20_calendar_reminder_empty", .empty),
            ("21_calendar_reminder_denied", .denied)
        ]
        for (name, preview) in cases {
            let state = NotchState(metrics: metrics, reminders: ReminderService(preview: preview))
            state.disableLiveRefresh = true
            state.isExpanded = true
            state.tab = .calendar
            state.calendarAuthorized = true
            state.battery = BatteryInfo(level: 0.73)
            state.monthEvents = [
                CalEvent(id: "fixture-a", title: "Project catch-up", start: now.addingTimeInterval(3600),
                         end: now.addingTimeInterval(5400), isAllDay: false, colorComponents: [0.3, 0.65, 1, 1]),
                CalEvent(id: "fixture-b", title: "Coffee break", start: now.addingTimeInterval(7200),
                         end: now.addingTimeInterval(8100), isAllDay: false, colorComponents: [1, 0.6, 0.4, 1])
            ]
            render(state, size: metrics.expandedSize, to: base.appendingPathComponent("\(name).png"))        }
    }
}
