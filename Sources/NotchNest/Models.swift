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
    var level: Double = 1.0        // 0...1
    var isCharging: Bool = false
    var isPluggedIn: Bool = false
    var hasBattery: Bool = true

    var percent: Int { Int((level * 100).rounded()) }
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
    case shelf = "Shelf"

    var symbol: String {
        switch self {
        case .music: return "music.note"
        case .calendar: return "calendar"
        case .shelf: return "tray.full"
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
