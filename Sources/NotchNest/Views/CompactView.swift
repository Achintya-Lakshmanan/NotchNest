import SwiftUI

/// The collapsed pill: meeting/art peeks on the left, charging bolt or
/// equalizer on the right, with the notch cutout in the gap between.
struct CompactView: View {
    @EnvironmentObject var state: NotchState
    @ObservedObject private var settings = Settings.shared
    let metrics: NotchMetrics

    private var showMeeting: Bool {
        settings.showMeetingCountdown && settings.isEnabled(.calendar) && state.imminentEvent != nil
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left widget — running timer first, then meeting, art, shelf.
            HStack {
                if state.timerRunning {
                    TimerPill(remaining: state.timerRemaining)
                        .transition(.scale.combined(with: .opacity))
                } else if showMeeting, let ev = state.imminentEvent {
                    MeetingPill(event: ev)
                        .transition(.scale.combined(with: .opacity))
                } else if let np = state.nowPlaying {
                    ArtworkView(image: state.artwork, title: np.title, size: 22, corner: 5)
                        .transition(.scale.combined(with: .opacity))
                } else if !state.shelf.isEmpty {
                    ZStack {
                        Image(systemName: "tray.full.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                        Text("\(state.shelf.count)")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 11, height: 11)
                            .background(.white, in: Circle())
                            .offset(x: 9, y: -8)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(width: 50)
            .padding(.leading, 6)

            // Notch cutout gap
            Spacer(minLength: metrics.notchWidth - 16)

            // Right widget — charging, equalizer when playing, else battery % per schedule.
            HStack {
                Spacer(minLength: 0)
                TimelineView(.periodic(from: .now, by: 60)) { _ in
                    if state.battery.isCharging {
                        if settings.isBatteryPercentVisibleInCompact(percent: state.battery.percent) {
                            CompactChargingDisplay(battery: state.battery)
                                .transition(.scale.combined(with: .opacity))
                        } else {
                            ChargingBadge(battery: state.battery, showPercent: false)
                                .transition(.scale.combined(with: .opacity))
                        }
                    } else if let np = state.nowPlaying {
                        EqualizerView(playing: np.isPlaying, color: .white)
                            .transition(.scale.combined(with: .opacity))
                    } else if settings.isBatteryPercentVisibleInCompact(percent: state.battery.percent), state.battery.hasBattery {
                        CompactBattery(battery: state.battery)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .frame(width: 50)
            .padding(.trailing, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
