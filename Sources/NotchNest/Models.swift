import AppKit
import SwiftUI

// MARK: - Notch geometry

struct NotchMetrics {
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var screenFrame: CGRect

    /// Size of the collapsed pill hugging the notch.
    var compactSize: CGSize {
        CGSize(width: notchWidth + 2 * 56, height: max(notchHeight, 32))
    }

    /// Size of the expanded card hanging below the notch. The first `notchHeight`
    /// points sit behind the physical notch, so add that to keep content visible.
    /// One size for every tab (no resize jump between them).
    var expandedSize: CGSize {
        CGSize(width: 540, height: 250 + notchHeight)
    }

    /// Small banner for transient Bluetooth toasts (much smaller than expanded).
    var toastSize: CGSize {
        CGSize(width: 380, height: 64 + notchHeight)
    }

    /// Compact pill for volume/brightness HUDs.
    var hudSize: CGSize {
        CGSize(width: max(notchWidth + 2 * 70, 260), height: 38 + notchHeight)
    }
}

// MARK: - Now Playing

enum MediaApp: String {
    case music = "Music"
    case spotify = "Spotify"

    var bundleID: String {
        switch self {
        case .music: return "com.apple.Music"
        case .spotify: return "com.spotify.client"
        }
    }
}

struct NowPlaying: Equatable {
    var app: MediaApp
    var title: String
    var artist: String
    var album: String
    var isPlaying: Bool
    var elapsed: Double
    var duration: Double
    var artworkURL: String?

    /// Identity for the track, ignoring transient playback position.
    var trackKey: String { "\(app.rawValue)|\(title)|\(artist)|\(album)" }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(elapsed / duration, 0), 1)
    }
}

// MARK: - Battery

struct BatteryInfo: Equatable {
    /// Above this level, the closed notch hides the % readout (bolt/equalizer still allowed).
    static let compactPercentThreshold = 65

    var level: Double = 1.0        // 0...1
    var isCharging: Bool = false
    var isPluggedIn: Bool = false
    var hasBattery: Bool = true
    /// Minutes until 100% from IOKit; -1 when unknown/calculating.
    var timeToFullChargeMinutes: Int?

    var percent: Int { Int((level * 100).rounded()) }

    /// Estimated minutes until 80% while charging; nil when already ≥80% or unknown.
    var minutesTo80: Int? {
        guard isCharging, level < 0.80 else { return nil }
        guard let timeToFull = timeToFullChargeMinutes, timeToFull >= 0 else { return nil }
        guard level < 1.0 else { return nil }
        let remaining = Double(timeToFull) * (0.80 - level) / (1.0 - level)
        return max(1, Int(remaining.rounded()))
    }
}

// MARK: - Shelf

struct ShelfItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    var name: String { url.lastPathComponent }
    var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }

    static func == (lhs: ShelfItem, rhs: ShelfItem) -> Bool { lhs.id == rhs.id }
}

// MARK: - Tabs

enum NotchTab: String, CaseIterable {
    case music = "Music"
    case calendar = "Calendar"
    case weather = "Weather"
    case timer = "Timer"
    case mirror = "Mirror"
    case shelf = "Shelf"

    var symbol: String {
        switch self {
        case .music: return "music.note"
        case .calendar: return "calendar"
        case .weather: return "cloud.sun.fill"
        case .timer: return "timer"
        case .mirror: return "camera.fill"
        case .shelf: return "tray.full"
        }
    }
}

func formatMMSS(_ t: TimeInterval) -> String {
    let s = Int(t.rounded())
    return String(format: "%d:%02d", s / 60, s % 60)
}

// MARK: - Generic alert toast (rain, battery, …)

struct AlertToast: Equatable {
    var symbol: String
    var title: String
    var subtitle: String
    var tint: Color
}

// MARK: - Weather

struct HourForecast: Identifiable, Equatable {
    var id: String          // ISO time string
    var label: String       // "Now", "2 PM", …
    var temp: Int
    var code: Int
    var isDay: Bool
    var precip: Int         // precipitation probability %
}

struct WeatherInfo: Equatable {
    var temp: Int
    var high: Int
    var low: Int
    var unit: String        // "°F" / "°C"
    var code: Int           // WMO weather code
    var isDay: Bool
    var city: String
    var hourly: [HourForecast] = []

    var symbol: String { WeatherInfo.symbol(code: code, isDay: isDay) }

    static func isPrecip(_ code: Int) -> Bool {
        switch code {
        case 51...67, 71...77, 80...86, 95...99: return true
        default: return false
        }
    }

    static func symbol(code: Int, isDay: Bool) -> String {
        switch code {
        case 0:           return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2:        return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3:           return "cloud.fill"
        case 45, 48:      return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67: return "cloud.rain.fill"
        case 71, 73, 75, 77:     return "snowflake"
        case 80, 81, 82:  return "cloud.heavyrain.fill"
        case 85, 86:      return "cloud.snow.fill"
        case 95, 96, 99:  return "cloud.bolt.rain.fill"
        default:          return "cloud.fill"
        }
    }

    var summary: String {
        switch code {
        case 0:           return "Clear"
        case 1, 2:        return "Partly Cloudy"
        case 3:           return "Cloudy"
        case 45, 48:      return "Foggy"
        case 51, 53, 55:  return "Drizzle"
        case 56, 57:      return "Freezing Drizzle"
        case 61, 63, 65:  return "Rain"
        case 66, 67:      return "Freezing Rain"
        case 71, 73, 75, 77: return "Snow"
        case 80, 81, 82:  return "Showers"
        case 85, 86:      return "Snow Showers"
        case 95:          return "Thunderstorm"
        case 96, 99:      return "Thunderstorm"
        default:          return "—"
        }
    }
}

// MARK: - HUD (volume / brightness)

struct HUDInfo: Equatable {
    enum Kind: Equatable { case volume, muted, brightness, keyboard }
    var kind: Kind
    var value: Double   // 0...1

    var symbol: String {
        switch kind {
        case .muted: return "speaker.slash.fill"
        case .volume:
            if value <= 0 { return "speaker.fill" }
            if value < 0.34 { return "speaker.wave.1.fill" }
            if value < 0.67 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        case .brightness: return "sun.max.fill"
        case .keyboard: return "keyboard"
        }
    }
}

// MARK: - Bluetooth

struct BTDevice: Identifiable, Equatable {
    var address: String
    var name: String
    var batteryMain: Int?
    var batteryLeft: Int?
    var batteryRight: Int?
    var batteryCase: Int?
    var minorType: String?

    var id: String { address }

    /// Best single number to show (AirPods report left/right; pick the min).
    var primaryBattery: Int? {
        let parts = [batteryLeft, batteryRight, batteryMain].compactMap { $0 }
        return parts.min()
    }

    var hasAnyBattery: Bool {
        primaryBattery != nil || batteryCase != nil
    }

    var symbol: String {
        let t = (minorType ?? "").lowercased()
        if t.contains("headphone") || name.lowercased().contains("airpod") { return "airpods" }
        if t.contains("keyboard") { return "keyboard" }
        if t.contains("mouse") { return "magicmouse" }
        if t.contains("speaker") || t.contains("audio") { return "hifispeaker" }
        return "dot.radiowaves.left.and.right"
    }
}

struct BTToast: Equatable {
    enum Kind: Equatable { case connected, disconnected, lowBattery }
    var device: BTDevice
    var kind: Kind

    var title: String { device.name }
    var subtitle: String {
        switch kind {
        case .connected: return "Connected"
        case .disconnected: return "Disconnected"
        case .lowBattery: return "Low Battery"
        }
    }
    var showsDeviceBattery: Bool { kind != .disconnected }
    var isAlert: Bool { kind == .lowBattery }
}

// MARK: - Calendar

struct CalEvent: Identifiable, Equatable {
    let id: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var colorComponents: [CGFloat]   // RGBA
    var videoURL: URL? = nil

    var color: Color {
        guard colorComponents.count == 4 else { return .accentColor }
        return Color(.sRGB,
                     red: colorComponents[0],
                     green: colorComponents[1],
                     blue: colorComponents[2],
                     opacity: colorComponents[3])
    }

    var isPast: Bool { end < Date() }
    var isNow: Bool { start <= Date() && end >= Date() }
}
