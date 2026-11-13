import SwiftUI
import UniformTypeIdentifiers

struct NotchRootView: View {
    @ObservedObject var state: NotchState
    @ObservedObject private var settings = Settings.shared
    @State private var dropTargeted = false

    var body: some View {
        ZStack {
            // The black notch body.
            NotchShape()
                .fill(.black)
                // Album-art tint blended into the top of the card.
                .overlay {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        let c = state.artworkColor ?? .clear
                        let visible = state.musicPresentationActive && showArtworkTint(now: context.date)
                        NotchShape()
                            .fill(presentationInset > 0
                                  // Open card: tint starts just below the hardware notch.
                                  ? LinearGradient(colors: [c.opacity(0.7), c.opacity(0.0)],
                                                   startPoint: .top, endPoint: .center)
                                  // Collapsed pill: rise from the bottom so there is no
                                  // coloured seam against the black camera housing.
                                  : LinearGradient(stops: [
                                        .init(color: c.opacity(0), location: 0),
                                        .init(color: c.opacity(0), location: 0.2),
                                        .init(color: c.opacity(0.4), location: 1),
                                    ], startPoint: .top, endPoint: .bottom))
                            .padding(.top, presentationInset)
                            .opacity(visible ? 1 : 0)
                            .animation(.easeInOut(duration: 1.2), value: visible)
                            .animation(.easeInOut(duration: 0.5), value: state.artworkColor)
                    }
                }
                // Weather paints the whole card edge-to-edge (no black frame around the sky).
                .overlay {
                    if let w = state.weather, showsWeatherSky {
                        let notch = state.metrics.notchHeight / state.metrics.expandedSize.height
                        let sky = WeatherPane.sky(w)
                        NotchShape()
                            .fill(LinearGradient(stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black, location: notch),
                                .init(color: sky[0], location: min(1, notch + 0.22)),
                                .init(color: sky[1], location: 1),
                            ], startPoint: .top, endPoint: .bottom))
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: showsWeatherSky)
                // Only stroke for transient feedback (drop / just-charged), never by default.
                .overlay {
                    if strokeWidth > 0 {
                        NotchShape().stroke(strokeColor, lineWidth: strokeWidth)
                    }
                }
                // Soft glow only while charging; otherwise no halo (keeps edges clean).
                .shadow(color: state.chargeFlash ? .green.opacity(0.45) : .clear,
                       radius: state.chargeFlash ? 14 : 0)

            // Timer countdown ring tracing the collapsed notch (the open Timer tab
            // has its own ring, so the outline would just look like a stray border).
            if state.timerRunning && !state.isExpanded {
                NotchShape()
                    .trim(from: 0, to: state.timerProgress)
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .animation(.linear(duration: 0.5), value: state.timerProgress)
            }

            if let hud = state.hud, !state.isExpanded {
                HUDView(hud: hud)
                    .padding(.top, state.metrics.notchHeight)
                    .padding(.bottom, 8)
                    .transition(.opacity)
            } else if let toast = state.btPopup, !state.isExpanded {
                BTPopupCard(toast: toast, mac: state.battery)
                    .padding(.top, state.metrics.notchHeight)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .top)))
            } else if let alert = state.alert, !state.isExpanded {
                AlertCard(toast: alert)
                    .padding(.top, state.metrics.notchHeight)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .top)))
            } else if state.isExpanded {
                ExpandedView()
                    .environmentObject(state)
                    .padding(.top, state.metrics.notchHeight)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            } else {
                CompactView(metrics: state.metrics)
                    .environmentObject(state)
                    .transition(.opacity)
            }

            if dropTargeted {
                NotchShape()
                    .fill(.white.opacity(0.08))
                Text("Drop to stash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted.animation(.easeOut(duration: 0.15))) { providers in
            handleDrop(providers)
        }
    }

    private func showArtworkTint(now: Date) -> Bool {
        if state.isExpanded { return true }
        return settings.isMusicVisibleInCompact(now: now)
    }

    private var showsWeatherSky: Bool {
        state.isExpanded && state.tab == .weather && !state.showingPreferences
            && !state.showingMenuBarApps && state.hud == nil && state.btPopup == nil && state.alert == nil
    }

    private var presentationInset: CGFloat {
        state.isExpanded || state.hud != nil || state.btPopup != nil || state.alert != nil
            ? state.metrics.notchHeight : 0
    }

    private var strokeColor: Color {
        if dropTargeted { return .white.opacity(0.5) }
        if state.chargeFlash { return .green.opacity(0.7) }
        return .clear
    }

    private var strokeWidth: CGFloat {
        if dropTargeted { return 1.5 }
        if state.chargeFlash { return 1.5 }
        return 0   // no default edge — solid black, no transparent outline
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            handled = true
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { state.addToShelf(url) }
            }
        }
        return handled
    }
}
