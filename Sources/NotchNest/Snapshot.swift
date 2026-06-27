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

        // 1. Expanded — music + charging
        let s1 = NotchState(metrics: metrics)
        s1.isExpanded = true
        s1.tab = .music
        s1.nowPlaying = NowPlaying(app: .music, title: "Midnight City", artist: "M83",
                                   album: "Hurry Up, We're Dreaming", isPlaying: true,
                                   elapsed: 96, duration: 244, artworkURL: nil)
        s1.battery = BatteryInfo(level: 0.62, isCharging: true, isPluggedIn: true, hasBattery: true)
        // Pull real Apple Music artwork synchronously so the tint is realistic.
        if let s = NSAppleScript(source: "tell application \"Music\"\nif it is running then\ntry\nreturn (data of artwork 1 of current track)\non error\nreturn missing value\nend try\nend if\nend tell") {
            var err: NSDictionary?
            let desc = s.executeAndReturnError(&err)
            if err == nil, !desc.data.isEmpty, let img = NSImage(data: desc.data) {
                s1.artwork = img
                s1.artworkColor = ColorExtractor.vibrant(from: img).map(Color.init)
            }
        }
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
            CalEvent(id: "b", title: "ENT Specialist Checkup", start: now.addingTimeInterval(3600),
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
        s4.btPopup = BTToast(device: BTDevice(address: "x", name: "Achintya's AirPods Pro",
                                              batteryMain: nil, batteryLeft: 97, batteryRight: 97,
                                              batteryCase: 82, minorType: "Headphones"),
                             kind: .connected)
        s4.battery = BatteryInfo(level: 0.62, isCharging: true, isPluggedIn: true, hasBattery: true)
        render(s4, size: metrics.toastSize, to: base.appendingPathComponent("4_bt_popup.png"))

        // 6 & 7. Disconnect + low-battery toasts
        let airpods = BTDevice(address: "x", name: "Achintya's AirPods Pro",
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

        // 8. Weather
        let s8 = NotchState(metrics: metrics)
        s8.isExpanded = true
        s8.tab = .weather
        s8.weather = WeatherInfo(temp: 72, high: 78, low: 61, unit: "°F",
                                 code: 1, isDay: true, city: "San Francisco",
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

        // 5. Compact — playing + charging
        let s5 = NotchState(metrics: metrics)
        s5.nowPlaying = s1.nowPlaying
        s5.battery = BatteryInfo(level: 0.62, isCharging: true, isPluggedIn: true, hasBattery: true)
        render(s5, size: metrics.compactSize, to: base.appendingPathComponent("5_compact_charging.png"))

        return true
    }

    private static func render(_ state: NotchState, size: CGSize, to url: URL) {
        let content = ZStack {
            // Stand-in wallpaper so we can see the card edges / transparency.
            LinearGradient(colors: [Color(white: 0.30), Color(white: 0.18)],
                           startPoint: .top, endPoint: .bottom)
            NotchRootView(state: state).environmentObject(state)
        }
        .frame(width: size.width, height: size.height)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }
}
