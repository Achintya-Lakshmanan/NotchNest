import SwiftUI
import CoreAudio

// MARK: - Equalizer

/// Animated bars that dance while music plays; flat when paused.
struct EqualizerView: View {
    var playing: Bool
    var color: Color = .white
    var bars: Int = 4

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: !playing)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(0..<bars, id: \.self) { i in
                    Capsule()
                        .fill(color)
                        .frame(width: 2.5, height: barHeight(index: i, time: t))
                }
            }
            .frame(height: 16, alignment: .center)
        }
    }

    private func barHeight(index: Int, time: Double) -> CGFloat {
        guard playing else { return 3 }
        let phase = Double(index) * 1.3
        let v = (sin(time * 7 + phase) + 1) / 2          // 0...1
        let v2 = (sin(time * 11 + phase * 0.7) + 1) / 2
        let mix = (v * 0.6 + v2 * 0.4)
        return 4 + CGFloat(mix) * 12
    }
}

// MARK: - Artwork

struct ArtworkView: View {
    var image: NSImage?
    var title: String
    var size: CGFloat
    var corner: CGFloat = 8

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.4, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        )
    }

    private var gradientColors: [Color] {
        let hue = Double(abs(title.hashValue) % 360) / 360.0
        return [
            Color(hue: hue, saturation: 0.7, brightness: 0.85),
            Color(hue: (hue + 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.8, brightness: 0.55),
        ]
    }
}

// MARK: - Battery

struct BatteryView: View {
    var battery: BatteryInfo

    private var fillColor: Color {
        if battery.isCharging || battery.isPluggedIn { return .green }
        if battery.level <= 0.15 { return .red }
        if battery.level <= 0.30 { return .yellow }
        return .white
    }

    var body: some View {
        HStack(spacing: 5) {
            Text("\(battery.percent)%")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .monospacedDigit()

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(.white.opacity(0.45), lineWidth: 1)
                    .frame(width: 24, height: 12)

                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(fillColor)
                    .frame(width: max(2, 22 * battery.level), height: 9)
                    .padding(.leading, 1)

                if battery.isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(.black.opacity(0.7))
                        .frame(width: 24, height: 12)
                }
            }
            // little nub
            .overlay(alignment: .trailing) {
                Capsule()
                    .fill(.white.opacity(0.45))
                    .frame(width: 1.5, height: 5)
                    .offset(x: 2.5)
            }
        }
    }
}

// MARK: - Charging

/// A battery that repeatedly "fills" with a green sweep while charging.
struct AnimatedChargingBattery: View {
    var level: Double
    var width: CGFloat = 26
    var height: CGFloat = 13

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let sweep = level + (1 - level) * ((sin(t * 2.2) + 1) / 2)   // level → full → level
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(.white.opacity(0.5), lineWidth: 1)
                    .frame(width: width, height: height)

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(LinearGradient(colors: [.green, .mint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(2, (width - 3) * sweep), height: height - 4)
                    .padding(.leading, 1.5)

                Image(systemName: "bolt.fill")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(.white)
                    .shadow(color: .green.opacity(0.9), radius: 2)
                    .frame(width: width, height: height)
            }
            .overlay(alignment: .trailing) {
                Capsule().fill(.white.opacity(0.5))
                    .frame(width: 1.5, height: 5)
                    .offset(x: 2.5)
            }
        }
    }
}

/// Small battery readout for the collapsed pill (laptop charge).
struct CompactBattery: View {
    var battery: BatteryInfo

    private var fill: Color {
        if battery.level <= 0.15 { return .red }
        if battery.level <= 0.30 { return .yellow }
        return .white
    }

    var body: some View {
        HStack(spacing: 3) {
            Text("\(battery.percent)%")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .strokeBorder(.white.opacity(0.5), lineWidth: 1)
                    .frame(width: 18, height: 10)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(fill)
                    .frame(width: max(2, 16 * battery.level), height: 7)
                    .padding(.leading, 1)
            }
        }
        .foregroundStyle(.white.opacity(0.9))
    }
}

/// Compact charging indicator for the collapsed pill: a pulsing bolt
/// (percent is intentionally hidden here — laptop charge only shows on hover).
struct ChargingBadge: View {
    var battery: BatteryInfo
    var showPercent: Bool = true

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let pulse = (sin(t * 3) + 1) / 2
            HStack(spacing: 3) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(.green)
                    .shadow(color: .green.opacity(0.4 + 0.6 * pulse), radius: 3)
                    .scaleEffect(0.9 + 0.15 * pulse)
                if showPercent {
                    Text("\(battery.percent)%")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
            }
        }
    }
}

// MARK: - Bluetooth connect popup

struct BTPopupCard: View {
    let toast: BTToast
    let mac: BatteryInfo

    private var device: BTDevice { toast.device }

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: device.symbol)
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(.white)
                if toast.kind == .disconnected {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white, .gray)
                } else if toast.kind == .lowBattery {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.black, .yellow)
                }
            }
            .frame(width: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(toast.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(toast.subtitle)
                    .font(.system(size: 10, weight: toast.isAlert ? .semibold : .regular))
                    .foregroundStyle(toast.isAlert ? .yellow : .white.opacity(0.5))

                if toast.showsDeviceBattery {
                    HStack(spacing: 8) {
                        if device.batteryLeft != nil || device.batteryRight != nil {
                            if let l = device.batteryLeft { BatteryPill(label: "L", pct: l) }
                            if let r = device.batteryRight { BatteryPill(label: "R", pct: r) }
                            if let c = device.batteryCase { BatteryPill(label: "Case", pct: c, symbol: "earbuds.case") }
                        } else if let m = device.primaryBattery {
                            BatteryPill(label: "", pct: m)
                        }
                        if mac.hasBattery {
                            BatteryPill(label: "Mac", pct: mac.percent,
                                        symbol: mac.isCharging ? "bolt.fill" : nil,
                                        tint: mac.isCharging ? .green : nil)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct BatteryPill: View {
    var label: String
    var pct: Int
    var symbol: String? = nil
    var tint: Color? = nil

    private var color: Color {
        if let tint { return tint }
        if pct <= 20 { return .red }
        return .white
    }

    var body: some View {
        HStack(spacing: 3) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 9, weight: .bold))
            } else if !label.isEmpty {
                Text(label).font(.system(size: 9, weight: .bold))
            }
            Text("\(pct)%")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(.white.opacity(0.1), in: Capsule())
    }
}

// MARK: - Battery cluster (Mac alone; AirPods on hover)

struct BatteryCluster: View {
    @EnvironmentObject var state: NotchState

    private var btDevice: BTDevice? {
        state.btDevices.first(where: { $0.hasAnyBattery })
    }

    var body: some View {
        HStack(spacing: 8) {
            // Both batteries when expanded: AirPods (if connected) + Mac.
            if let dev = btDevice, let pct = dev.primaryBattery {
                HStack(spacing: 4) {
                    Image(systemName: dev.symbol)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                    Text("\(pct)%")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(pct <= 20 ? .red : .white.opacity(0.85))
                        .monospacedDigit()
                }
                .transition(.opacity)
            }

            macBattery
        }
    }

    @ViewBuilder private var macBattery: some View {
        if state.battery.isCharging {
            HStack(spacing: 5) {
                Text("\(state.battery.percent)%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.green)
                    .monospacedDigit()
                AnimatedChargingBattery(level: state.battery.level)
            }
        } else if state.battery.hasBattery {
            BatteryView(battery: state.battery)
        }
    }
}

// MARK: - Meeting countdown pill (collapsed notch)

struct MeetingPill: View {
    let event: CalEvent

    var body: some View {
        TimelineView(.periodic(from: .now, by: 20)) { _ in
            HStack(spacing: 4) {
                Circle()
                    .fill(isNow ? Color.green : event.color)
                    .frame(width: 6, height: 6)
                Text(label)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
        }
    }

    private var isNow: Bool {
        let now = Date(); return event.start <= now && event.end > now
    }

    private var label: String {
        if isNow { return "Now" }
        let mins = Int(ceil(event.start.timeIntervalSinceNow / 60))
        if mins < 60 { return "\(mins)m" }
        return "\(mins / 60)h"
    }
}

// MARK: - Audio output switcher

struct OutputDeviceMenu: View {
    @State private var devices: [AudioDevice] = []
    @State private var current: AudioDeviceID?

    var body: some View {
        Menu {
            ForEach(devices) { device in
                Button {
                    AudioOutput.setDefault(device.id)
                    current = device.id
                } label: {
                    if device.id == current {
                        Label(device.name, systemImage: "checkmark")
                    } else {
                        Text(device.name)
                    }
                }
            }
        } label: {
            Image(systemName: "hifispeaker.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onAppear(perform: refresh)
    }

    private func refresh() {
        devices = AudioOutput.devices()
        current = AudioOutput.currentDefault()
    }
}

// MARK: - Circular icon button

struct CircleButton: View {
    var symbol: String
    var size: CGFloat = 16
    var action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: size + 18, height: size + 18)
                .background(.white.opacity(pressed ? 0.22 : 0.10), in: Circle())
                .scaleEffect(pressed ? 0.9 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { pressed = hovering }
        }
    }
}
