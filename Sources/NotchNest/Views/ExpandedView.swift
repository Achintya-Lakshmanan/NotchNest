import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

struct ExpandedView: View {
    @EnvironmentObject var state: NotchState
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        VStack(spacing: 8) {
            topBar
            Divider().overlay(.white.opacity(0.08))
            // Fixed slot: Color.clear takes exactly the leftover space, and the pane
            // lives in its overlay so a tall pane can never grow the stack and shift
            // the top bar (every tab stays pixel-aligned).
            Color.clear.overlay(alignment: .top) { content }
                .clipped()
        }
        // NotchRootView reserves the black strip behind the camera cutout.
        .padding(.top, 8)
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
        .foregroundStyle(.white)
        .onAppear(perform: ensureValidTab)
        .onChange(of: settings.disabledTabs) { _, _ in ensureValidTab() }
    }

    private var content: some View {
            Group {
                if state.showingMenuBarApps {
                    MenuBarAppsPane(service: state.menuBarApps, liveRefresh: !state.disableLiveRefresh)
                } else if state.showingPreferences {
                    SettingsPane()
                } else {
                    switch state.tab {
                    case .music: MusicPane()
                    case .calendar: CalendarPane()
                    case .timer: TimerPane()
                    case .codex: AIUsagePane(service: state.codexUsage, claude: state.claudeUsage,
                                          liveRefresh: !state.disableLiveRefresh)
                    case .mirror: MirrorPane()
                    case .shelf: ShelfPane()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func ensureValidTab() {
        if !settings.isEnabled(state.tab), let first = settings.enabledTabs.first {
            state.tab = first
        }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                ViewThatFits(in: .horizontal) {
                    Text(Self.timeFormatter.string(from: Date())).fixedSize()
                    Text(Date().formatted(.dateTime.hour().minute())).fixedSize()
                }
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            // Equal flexible side columns keep the tabs centred whatever the
            // time or battery text width.
            .frame(maxWidth: .infinity, alignment: .leading)

            // Tab switcher (only enabled tabs)
            HStack(spacing: 3) {
                ForEach(settings.enabledTabs, id: \.self) { tab in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            state.showingPreferences = false
                            state.showingMenuBarApps = false
                            state.tab = tab
                        }
                    } label: {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(!state.showingPreferences && !state.showingMenuBarApps && state.tab == tab ? .white : .white.opacity(0.45))
                            .frame(width: 26, height: 22)
                            .contentShape(Rectangle())
                            .background(!state.showingPreferences && !state.showingMenuBarApps && state.tab == tab ? .white.opacity(0.16) : .clear,
                                       in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help(tab.title)
                    .accessibilityLabel(tab.title)
                }
                Button {
                    state.showingPreferences = false
                    state.showingMenuBarApps.toggle()
                } label: {
                    Image(systemName: "menubar.rectangle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(state.showingMenuBarApps ? .white : .white.opacity(0.45))
                        .frame(width: 26, height: 22)
                        .contentShape(Rectangle())
                        .background(state.showingMenuBarApps ? .white.opacity(0.16) : .clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Menu bar apps • Control Option M")
                .accessibilityLabel("Menu bar apps")
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        state.showingMenuBarApps = false
                        state.showingPreferences.toggle()
                    }
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(state.showingPreferences ? .white : .white.opacity(0.45))
                        .frame(width: 26, height: 22)
                        .contentShape(Rectangle())
                        .background(state.showingPreferences ? .white.opacity(0.16) : .clear,
                                   in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Preferences")
            }
            .fixedSize(horizontal: true, vertical: false)

            ViewThatFits(in: .horizontal) {
                BatteryCluster(showETA: true, showAccessory: true)
                BatteryCluster(showETA: false, showAccessory: true)
                BatteryCluster(showETA: false, showAccessory: false)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE h:mm a"
        return f
    }()
}

// MARK: - Music pane

struct MusicPane: View {
    @EnvironmentObject var state: NotchState

    var body: some View {
        if let np = state.displayedNowPlaying {
            HStack(spacing: 18) {
                ArtworkView(image: state.artwork, title: np.title, size: 116, corner: 18)
                    .shadow(color: .black.opacity(0.45), radius: 8, y: 4)

                VStack(alignment: .leading, spacing: 8) {
                    if state.showingLyrics && Settings.shared.lyricsEnabled {
                        LyricsView()
                            .frame(height: 58, alignment: .topLeading)
                            .transition(.opacity)
                    } else {
                        Text(np.title.isEmpty ? "Unknown" : np.title)
                            .font(.system(size: 17, weight: .bold))
                            .lineLimit(1)
                        Text(np.artist)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }

                    // Extrapolated between 2s polls so the bar and times move smoothly.
                    TimelineView(.periodic(from: .now, by: np.isPlaying ? 0.5 : 60)) { context in
                        let elapsed = state.estimatedElapsed(at: context.date)
                        VStack(spacing: 3) {
                            ProgressBar(progress: np.duration > 0 ? elapsed / np.duration : 0,
                                        tint: state.artworkColor,
                                        onSeek: { state.seek(toFraction: $0) })
                                .frame(height: 14)
                            HStack {
                                Text(formatMMSS(elapsed))
                                Spacer()
                                Text("-" + formatMMSS(max(0, np.duration - elapsed)))
                            }
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.45))
                        }
                    }

                    HStack(spacing: 14) {
                        CircleButton(symbol: "backward.fill", size: 15) { state.previous() }
                        CircleButton(symbol: np.isPlaying ? "pause.fill" : "play.fill", size: 18) { state.togglePlay() }
                        CircleButton(symbol: "forward.fill", size: 15) { state.next() }
                        Spacer()
                        if let favorited = np.isFavorited {
                            IconToggle(symbol: favorited ? "heart.fill" : "heart",
                                       active: favorited, activeTint: .pink,
                                       help: favorited ? "Remove from Favourites" : "Add to Favourites") {
                                state.toggleFavorite()
                            }
                        }
                        if Settings.shared.lyricsEnabled {
                            IconToggle(symbol: "quote.bubble", active: state.showingLyrics, activeTint: .white,
                                       help: state.showingLyrics ? "Hide lyrics" : "Show lyrics") {
                                withAnimation(.easeInOut(duration: 0.2)) { state.toggleLyrics() }
                            }
                        }
                        OutputDeviceMenu(liveRefresh: !state.disableLiveRefresh)
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "music.note")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.white.opacity(0.4))
                Text("Nothing playing")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                Text("Play something in Music or Spotify")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Small icon button that lights up while active (heart, lyrics).
struct IconToggle: View {
    let symbol: String
    let active: Bool
    var activeTint: Color = .white
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(active ? activeTint : .white.opacity(0.7))
                .frame(width: 28, height: 28)
                .background(active ? activeTint.opacity(0.18) : .white.opacity(0.08), in: Circle())
                .contentShape(Circle())
                .symbolEffect(.bounce, value: active)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Synced lyrics: previous, current and next line, following playback.
struct LyricsView: View {
    @EnvironmentObject var state: NotchState

    var body: some View {
        Group {
            switch state.lyrics {
            case .synced(let lines):
                TimelineView(.periodic(from: .now, by: 0.25)) { context in
                    syncedLines(lines, index: Lyrics.currentIndex(in: lines, at: state.estimatedElapsed(at: context.date)))
                }
            case .plain(let text):
                ScrollView(showsIndicators: false) {
                    Text(text)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .instrumental:
                status("music.note", "Instrumental")
            case .unavailable:
                status("text.badge.xmark", "No lyrics found for this song")
            case .failed:
                status("wifi.exclamationmark", "Couldn't reach the lyrics service") {
                    Task { await state.loadLyricsIfNeeded() }
                }
            case nil:
                status("ellipsis", state.lyricsLoading ? "Finding lyrics…" : "")
            }
        }
        .task(id: state.nowPlaying?.trackKey) { await state.loadLyricsIfNeeded() }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func syncedLines(_ lines: [LyricLine], index: Int?) -> some View {
        let current: String = index.map { lines[$0].text } ?? "♪"
        let nextIndex = (index ?? -1) + 1
        let next: String? = nextIndex < lines.count ? lines[nextIndex].text : nil
        return VStack(alignment: .leading, spacing: 3) {
            songLine
            line(current, size: 15, opacity: 1, bold: true)
            line(next, size: 11, opacity: 0.5)
        }
        .animation(.easeInOut(duration: 0.25), value: index)
    }

    private func line(_ text: String?, size: CGFloat, opacity: Double, bold: Bool = false) -> some View {
        Text(text?.isEmpty == false ? text! : " ")
            .font(.system(size: size, weight: bold ? .bold : .medium))
            .foregroundStyle(.white.opacity(opacity))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .id(text)
    }

    /// Keeps the song identifiable while lyrics replace the title.
    private var songLine: some View {
        let np = state.nowPlaying
        return Text([np?.title, np?.artist].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.white.opacity(0.45))
            .lineLimit(1)
    }

    private func status(_ symbol: String, _ text: String, retry: (() -> Void)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            songLine
            HStack(spacing: 8) {
                Label(text, systemImage: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                if let retry {
                    Button("Retry", action: retry)
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9).frame(height: 20)
                        .background(.white.opacity(0.14), in: Capsule())
                        .disabled(state.lyricsLoading)
                }
            }
        }
    }
}

struct ProgressBar: View {
    var progress: Double
    var tint: Color?
    var onSeek: ((Double) -> Void)? = nil
    @State private var dragFraction: Double? = nil

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let frac = min(max(dragFraction ?? progress, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15)).frame(height: 5)
                Capsule().fill((tint ?? .white).opacity(0.95))
                    .frame(width: max(2, w * frac), height: 5)
                if onSeek != nil {
                    Circle().fill(.white)
                        .frame(width: 11, height: 11)
                        .shadow(color: .black.opacity(0.3), radius: 1)
                        .offset(x: max(0, min(w - 11, w * frac - 5.5)))
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in dragFraction = min(max(v.location.x / w, 0), 1) }
                    .onEnded { v in
                        let f = min(max(v.location.x / w, 0), 1)
                        onSeek?(f)
                        dragFraction = nil
                    }
            )
        }
    }
}

// MARK: - Shelf pane

struct ShelfPane: View {
    @EnvironmentObject var state: NotchState

    var body: some View {
        Group {
            if state.shelf.isEmpty {
                dropZone(large: true)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text("\(state.shelf.count) stashed")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                        Spacer()
                        Button { state.clearShelf() } label: {
                            Text("Clear all")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.8))
                                .padding(.horizontal, 10).frame(height: 24)
                                .background(.white.opacity(0.1), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        Button { state.airDrop(state.shelf.map(\.url)) } label: {
                            Label("AirDrop all", systemImage: "dot.radiowaves.right")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10).frame(height: 24)
                                .background(.blue, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(state.shelf) { item in
                                ShelfChip(item: item)
                            }
                            dropZone(large: false)
                        }
                        .padding(.horizontal, 2)
                        .padding(.vertical, 4)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .scaleEffect(state.justDropped ? 1.04 : 1)
    }

    /// Dashed target: the whole card accepts drops, this just shows where.
    private func dropZone(large: Bool) -> some View {
        VStack(spacing: large ? 8 : 4) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: large ? 24 : 16, weight: .light))
            Text(large ? "Drop files here to stash them, then AirDrop" : "Drop more")
                .font(.system(size: large ? 11.5 : 9.5, weight: .medium))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white.opacity(0.45))
        // Small tile matches a file chip (62pt label + 6pt padding each side; 78pt tall).
        .frame(maxWidth: large ? .infinity : 74, maxHeight: large ? .infinity : 78)
        .frame(width: large ? nil : 74, height: large ? nil : 78)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(.white.opacity(0.18), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])))
    }
}

struct ShelfChip: View {
    @EnvironmentObject var state: NotchState
    let item: ShelfItem
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: item.icon)
                .resizable()
                .frame(width: 40, height: 40)
            Text(item.name)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(width: 62, height: 22, alignment: .top)
                .help(item.name)
        }
        .padding(6)
        .background(.white.opacity(hovering ? 0.12 : 0.06),
                   in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button { state.removeFromShelf(item) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white, .black.opacity(0.5))
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if hovering {
                Button { state.airDrop([item.url]) } label: {
                    Image(systemName: "dot.radiowaves.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(.blue, in: Circle())
                }
                .buttonStyle(.plain)
                .help("AirDrop")
                .offset(x: 4, y: 4)
            }
        }
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
    }
}

// MARK: - Timer pane

struct TimerPane: View {
    @EnvironmentObject var state: NotchState
    private let presets = [1, 5, 10, 25]

    private var accent: Color { state.pomodoro?.phase == .rest ? .green : .orange }
    private var isIdle: Bool { !state.timerRunning && state.timerRemaining == state.timerDuration }

    var body: some View {
        HStack(spacing: 26) {
            ZStack {
                Circle().stroke(.white.opacity(0.12), lineWidth: 8)
                if isIdle {
                    // "Ready", not "done": the neutral track plus a thin accent hairline.
                    Circle().inset(by: 7).stroke(accent.opacity(0.8), lineWidth: 2)
                } else {
                    Circle()
                        .trim(from: 0, to: state.timerProgress)
                        .stroke(accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.5), value: state.timerProgress)
                }
                VStack(spacing: 1) {
                    Text(formatMMSS(state.timerRemaining))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Text(statusLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .frame(width: 136, height: 136)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    if isIdle {
                        pill("Start", icon: "play.fill", color: .orange, wide: true) { state.startTimer() }
                        stepper
                    } else {
                        pill(state.timerRunning ? "Pause" : "Resume",
                             icon: state.timerRunning ? "pause.fill" : "play.fill",
                             color: accent, wide: true) {
                            state.timerRunning ? state.pauseTimer() : state.startTimer()
                        }
                        pill("Reset", icon: "arrow.counterclockwise", color: .white.opacity(0.14)) {
                            state.resetTimer()
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("QUICK START")
                        .font(.system(size: 8.5, weight: .bold)).tracking(0.7)
                        .foregroundStyle(.white.opacity(0.4))
                    HStack(spacing: 6) {
                        ForEach(presets, id: \.self) { m in
                            pill("\(m)m", color: .white.opacity(0.1)) { state.setTimer(minutes: m) }
                        }
                    }
                }
                pill(state.pomodoro == nil ? "Pomodoro · 25 / 5" : "Pomodoro · round \(state.pomodoro!.round)",
                     icon: "leaf.fill", color: state.pomodoro == nil ? .white.opacity(0.1) : .green.opacity(0.3)) {
                    state.startPomodoro()
                }
                .help("25 min focus, 5 min break; a 15 min break every 4th round")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusLabel: String {
        if let p = state.pomodoro { return p.phase == .focus ? "focus · round \(p.round)" : "break" }
        if state.timerRunning { return "remaining" }
        return isIdle ? "ready" : "paused"
    }

    /// Custom length, in whole minutes.
    private var stepper: some View {
        HStack(spacing: 0) {
            stepButton("minus", -1)
            Text("\(Int(state.timerDuration / 60)) min")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(minWidth: 46)
            stepButton("plus", 1)
        }
        .foregroundStyle(.white)
        .frame(height: 28)
        .background(.white.opacity(0.1), in: Capsule())
    }

    private func stepButton(_ symbol: String, _ delta: Int) -> some View {
        Button { state.adjustTimer(byMinutes: delta) } label: {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 26, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(delta > 0 ? "One minute longer" : "One minute shorter")
    }

    private func pill(_ title: String, icon: String? = nil, color: Color, wide: Bool = false,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).font(.system(size: 10, weight: .bold)) }
                Text(title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, wide ? 14 : 11)
            .frame(height: 28)
            .background(color, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Mirror pane (front camera)

struct MirrorPane: View {
    @State private var camera = CameraSession()
    @State private var status = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        ZStack {
            if status == .authorized {
                CameraPreview(session: camera.session)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                    )
            } else if status == .notDetermined {
                grant("Allow camera to use the mirror") {
                    AVCaptureDevice.requestAccess(for: .video) { ok in
                        DispatchQueue.main.async {
                            status = ok ? .authorized : .denied
                            if ok { camera.start() }
                        }
                    }
                }
            } else {
                grant("Camera access denied — open Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            status = AVCaptureDevice.authorizationStatus(for: .video)
            if status == .authorized { camera.start() }
        }
        .onDisappear { camera.stop() }
    }

    private func grant(_ text: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "camera.fill")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.white.opacity(0.5))
            Button(text, action: action)
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(.white.opacity(0.15), in: Capsule())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Calendar pane (month grid + side panel)

struct CalendarPane: View {
    @EnvironmentObject var state: NotchState

    var body: some View {
        Group {
            if !state.calendarAuthorized {
                VStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("See your calendar in the notch")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                    Button("Grant Calendar Access") { state.requestCalendarAccess() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(.white.opacity(0.15), in: Capsule())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    MonthCalendarView()
                        .frame(width: 300)
                    Divider().overlay(.white.opacity(0.08))
                    DayEventsPanel()
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Reopening the notch or returning from another tab starts on today,
        // rather than retaining the last date browsed in a previous visit.
        .onAppear { state.goToToday() }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            state.goToToday()
        }
    }
}

struct MonthCalendarView: View {
    @EnvironmentObject var state: NotchState

    private let cal = Calendar.current
    private static let monthFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; return f
    }()
    private let weekdays = ["S", "M", "T", "W", "T", "F", "S"]

    private var isOnToday: Bool {
        cal.isDate(state.visibleMonth, equalTo: Date(), toGranularity: .month)
            && cal.isDateInToday(state.selectedDate)
    }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

    @ObservedObject private var settings = Settings.shared

    var body: some View {
        VStack(spacing: 3) {
            // Header
            HStack(spacing: 7) {
                Button { state.changeMonth(by: -1) } label: {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.7))

                Text(Self.monthFmt.string(from: state.visibleMonth))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)

                Button { state.changeMonth(by: 1) } label: {
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.7))

                Spacer()

                // Only offered once you've browsed away; space is kept so the header doesn't shift.
                Button { state.goToToday() } label: {
                    Text("Today")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9).frame(height: 20)
                        .background(.white.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain).help("Go to today")
                .opacity(isOnToday ? 0 : 1)
                .disabled(isOnToday)
                .accessibilityHidden(isOnToday)
                .animation(.easeOut(duration: 0.15), value: isOnToday)
            }

            // Weekday header
            HStack(spacing: 2) {
                ForEach(Array(weekdays.enumerated()), id: \.offset) { _, d in
                    Text(d)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(maxWidth: .infinity)
                }
            }

            // Day grid
            LazyVGrid(columns: columns, spacing: 1) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day { DayCell(day: day) } else { Color.clear.frame(height: 19) }
                }
            }
            Spacer(minLength: 0)
            if settings.showCalendarReminder {
                ReminderCard(service: state.reminders, liveRefresh: !state.disableLiveRefresh, compact: true)
            }
        }
    }

    /// Day numbers for the visible month, with leading nils for alignment.
    private var days: [Int?] {
        guard let range = cal.range(of: .day, in: .month, for: state.visibleMonth) else { return [] }
        let firstWeekday = cal.component(.weekday, from: state.visibleMonth) // 1 = Sunday
        let leading = firstWeekday - 1
        return Array(repeating: nil, count: leading) + range.map { Optional($0) }
    }
}

struct DayCell: View {
    @EnvironmentObject var state: NotchState
    let day: Int
    private let cal = Calendar.current

    private var date: Date {
        var comps = cal.dateComponents([.year, .month], from: state.visibleMonth)
        comps.day = day
        return cal.date(from: comps) ?? state.visibleMonth
    }
    private var isToday: Bool { cal.isDateInToday(date) }
    private var isSelected: Bool { cal.isDate(date, inSameDayAs: state.selectedDate) }
    private var isWeekend: Bool { cal.isDateInWeekend(date) }
    private var hasEvents: Bool { state.daysWithEvents.contains(day) }

    var body: some View {
        Button { state.select(date) } label: {
            // 19pt rows: a six-week month plus the reminder strip fit the fixed pane.
            Text("\(day)")
                .font(.system(size: 11.5, weight: isSelected || isToday ? .bold : .regular))
                .foregroundStyle(foreground)
                // Sit a little high so the event dot never touches the numerals.
                .offset(y: -1)
                .frame(width: 19, height: 19)
                .background(background)
                .overlay(alignment: .bottom) {
                    Circle()
                        .fill(hasEvents ? (isToday ? Color.white : Color.white.opacity(0.7)) : .clear)
                        .frame(width: 3, height: 3)
                        .offset(y: -1)
                }
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        if isToday { return .white }
        if isSelected { return .white }
        if isWeekend { return Color(red: 0.4, green: 0.7, blue: 1.0) }
        return .white.opacity(0.85)
    }

    @ViewBuilder private var background: some View {
        if isToday {
            Circle().fill(.red)
        } else if isSelected {
            Circle().fill(.white.opacity(0.18))
        }
    }
}

struct DayEventsPanel: View {
    @EnvironmentObject var state: NotchState

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("EEEMMMd"); return f
    }()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 8) {
                header(now: context.date)
                if state.showingDeadlines {
                    deadlineList(now: context.date)
                } else {
                    dayList
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func header(now: Date) -> some View {
        let urgent = state.deadlines.contains { $0.isUrgent(at: now) }
        return HStack(spacing: 6) {
            Text(state.showingDeadlines ? "Deadlines" : Self.dayFmt.string(from: state.selectedDate))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
            Spacer(minLength: 4)
            if !state.deadlines.isEmpty || state.showingDeadlines {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { state.showingDeadlines.toggle() }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: state.showingDeadlines ? "chevron.left" : "flag.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text(state.showingDeadlines ? "Events" : "\(state.deadlines.count)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                    .foregroundStyle(state.showingDeadlines ? .white : (urgent ? .orange : .white.opacity(0.8)))
                    .padding(.horizontal, 7).frame(height: 20)
                    .background((urgent && !state.showingDeadlines ? Color.orange : .white).opacity(0.14),
                                in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(state.showingDeadlines ? "Back to events" : "Upcoming deadlines")
                .accessibilityLabel(state.showingDeadlines ? "Show events" : "Show \(state.deadlines.count) upcoming deadlines")
            }
        }
    }

    @ViewBuilder private var dayList: some View {
        let events = state.selectedDayEvents
        if events.isEmpty {
            emptyState("calendar.day.timeline.left", "No events")
        } else {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(events) { ev in
                        CalendarRow(event: ev, onJoin: ev.videoURL != nil ? { state.join(ev) } : nil)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder private func deadlineList(now: Date) -> some View {
        if state.deadlines.isEmpty {
            emptyState("flag", "Nothing due in the next two weeks")
        } else {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 7) {
                    ForEach(state.deadlines) { deadline in
                        // Tap to jump to that day's events.
                        Button { withAnimation(.easeInOut(duration: 0.2)) { state.select(deadline.due) } } label: {
                            DeadlineRow(deadline: deadline, now: now).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func emptyState(_ symbol: String, _ text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(.white.opacity(0.3))
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DeadlineRow: View {
    let deadline: Deadline
    let now: Date

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("EEE"); return f
    }()

    /// Matches the day list: end-of-day markers read "Sun · Due by 11:59 PM".
    static func dueText(_ due: Date) -> String {
        let time = CalendarRow.timeFmt.string(from: due)
        let endOfDay = Calendar.current.component(.hour, from: due) == 23
            && Calendar.current.component(.minute, from: due) == 59
        return "\(dayFmt.string(from: due)) · " + (endOfDay ? "Due by \(time)" : "Due \(time)")
    }

    var body: some View {
        let urgent = deadline.isUrgent(at: now)
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(urgent ? Color.orange : deadline.color)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(deadline.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 5) {
                    Text(deadline.countdown(at: now))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(urgent ? .orange : .white.opacity(0.75))
                    Text(Self.dueText(deadline.due))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
        .help(deadline.fullTitle)
        .accessibilityElement(children: .combine)
    }
}

struct CalendarRow: View {
    let event: CalEvent
    var onJoin: (() -> Void)? = nil

    static let timeFmt: DateFormatter = {
        // Follows the system 12/24-hour setting.
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("jmm"); return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Group {
                if event.isDayMarker && !event.coversWholeDay {
                    Image(systemName: "flag.fill").font(.system(size: 8, weight: .bold)).foregroundStyle(event.color)
                } else {
                    Circle().fill(event.color)
                }
            }
            .frame(width: 8, height: 8)
            .padding(.top, 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(event.isPast ? 0.4 : 0.95))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(timeText)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                    if event.isNow && !event.isDayMarker {
                        Text("NOW")
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 5).padding(.vertical, 1.5)
                            .background(.green, in: Capsule())
                            .fixedSize()
                    }
                }
                if let place = event.location, !event.coversWholeDay {
                    Label(place, systemImage: "mappin")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                        .help(place)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .layoutPriority(-1)
            Spacer(minLength: 0)
            if let onJoin {
                // Icon-only so the time line keeps its full width.
                Button(action: onJoin) {
                    Image(systemName: "video.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(.green.opacity(0.9), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Join meeting")
                .accessibilityLabel("Join meeting")
                .padding(.top, 2)
                .layoutPriority(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(event.title)
    }

    /// Midnight registrar markers are deadlines ("Due by 11:59 PM"), not 12–1 AM events.
    private var timeText: String {
        if event.coversWholeDay { return "All day" }
        if event.isDayMarker {
            let due = Calendar.current.startOfDay(for: event.start).addingTimeInterval(24 * 3600 - 60)
            return "Due by \(Self.timeFmt.string(from: due))"
        }
        return "\(Self.timeFmt.string(from: event.start)) – \(Self.timeFmt.string(from: event.end))"
    }
}
