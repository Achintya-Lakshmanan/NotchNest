import SwiftUI
import UniformTypeIdentifiers

struct NotchRootView: View {
    @ObservedObject var state: NotchState
    @State private var dropTargeted = false

    var body: some View {
        ZStack {
            // The black notch body.
            NotchShape()
                .fill(.black)
                // Album-art tint blended into the top of the card.
                .overlay {
                    if let c = state.artworkColor {
                        NotchShape()
                            .fill(LinearGradient(colors: [c.opacity(0.7), c.opacity(0.0)],
                                                 startPoint: .top, endPoint: .center))
                            .animation(.easeInOut(duration: 0.5), value: state.artworkColor)
                    }
                }
                // Only stroke for transient feedback (drop / just-charged), never by default.
                .overlay {
                    if strokeWidth > 0 {
                        NotchShape().stroke(strokeColor, lineWidth: strokeWidth)
                    }
                }
                // Soft glow only while charging; otherwise no halo (keeps edges clean).
                .shadow(color: state.chargeFlash ? .green.opacity(0.45) : .clear,
                       radius: state.chargeFlash ? 14 : 0)

            // Timer countdown ring tracing the notch outline.
            if state.timerRunning {
                NotchShape()
                    .trim(from: 0, to: state.timerProgress)
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .animation(.linear(duration: 0.5), value: state.timerProgress)
            }

            if let hud = state.hud, !state.isExpanded {
                HUDView(hud: hud)
                    .padding(.top, max(4, state.metrics.notchHeight))
                    .padding(.bottom, 8)
                    .transition(.opacity)
            } else if let toast = state.btPopup, !state.isExpanded {
                BTPopupCard(toast: toast, mac: state.battery)
                    .padding(.top, max(6, state.metrics.notchHeight))
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .top)))
            } else if let alert = state.alert, !state.isExpanded {
                AlertCard(toast: alert)
                    .padding(.top, max(6, state.metrics.notchHeight))
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .top)))
            } else if state.isExpanded {
                ExpandedView()
                    .environmentObject(state)
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
