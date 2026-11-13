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
                    case .weather: WeatherPane()
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

            Spacer(minLength: 0)

            // Tab switcher (only enabled tabs)
            HStack(spacing: 4) {
                ForEach(settings.enabledTabs, id: \.self) { tab in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            state.showingPreferences = false
                            state.showingMenuBarApps = false
                            state.tab = tab
                        }
                    } label: {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(!state.showingPreferences && !state.showingMenuBarApps && state.tab == tab ? .white : .white.opacity(0.45))
                            .frame(width: 24, height: 20)
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
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(state.showingMenuBarApps ? .white : .white.opacity(0.45))
                        .frame(width: 24, height: 20)
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
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(state.showingPreferences ? .white : .white.opacity(0.45))
                        .frame(width: 26, height: 20)
                        .background(state.showingPreferences ? .white.opacity(0.16) : .clear,
                                   in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Preferences")
            }
            .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 0)

            BatteryCluster()
                .fixedSize(horizontal: true, vertical: false)
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
                    Text(np.title.isEmpty ? "Unknown" : np.title)
                        .font(.system(size: 17, weight: .bold))
                        .lineLimit(1)
                    Text(np.artist)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)

                    ProgressBar(progress: np.progress, tint: state.artworkColor,
                                onSeek: { state.seek(toFraction: $0) })
                        .frame(height: 14)
                        .padding(.top, 2)

                    HStack(spacing: 16) {
                        CircleButton(symbol: "backward.fill", size: 15) { state.previous() }
                        CircleButton(symbol: np.isPlaying ? "pause.fill" : "play.fill", size: 18) { state.togglePlay() }
                        CircleButton(symbol: "forward.fill", size: 15) { state.next() }
                        Spacer()
                        OutputDeviceMenu(liveRefresh: !state.disableLiveRefresh)
                        Text(np.app.rawValue)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.4))
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
                    .foregroundStyle(.white.opacity(0.5))
                Text("Play something in Music or Spotify")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.white.opacity(0.4))
                    Text("Drag files here to stash, then AirDrop")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 6) {
                    HStack {
                        Text("\(state.shelf.count) stashed")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                        Spacer()
                        Button { state.airDrop(state.shelf.map(\.url)) } label: {
                            Label("AirDrop all", systemImage: "dot.radiowaves.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 9).padding(.vertical, 4)
                                .background(.blue, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(state.shelf) { item in
                                ShelfChip(item: item)
                            }
                        }
                        .padding(.horizontal, 2)
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scaleEffect(state.justDropped ? 1.04 : 1)
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
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .frame(width: 58)
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

    var body: some View {
        HStack(spacing: 22) {
            ZStack {
                Circle().stroke(.white.opacity(0.12), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: state.timerProgress)
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: state.timerProgress)
                VStack(spacing: 1) {
                    Text(formatMMSS(state.timerRemaining))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Text(state.timerRunning ? "remaining" : "timer")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(width: 124, height: 124)

            VStack(alignment: .leading, spacing: 10) {
                if state.timerRunning || state.timerRemaining != state.timerDuration {
                    HStack(spacing: 8) {
                        pill(state.timerRunning ? "Pause" : "Resume",
                             icon: state.timerRunning ? "pause.fill" : "play.fill",
                             color: .orange) {
                            state.timerRunning ? state.pauseTimer() : state.startTimer()
                        }
                        pill("Reset", icon: "arrow.counterclockwise", color: .white.opacity(0.15)) {
                            state.resetTimer()
                        }
                    }
                }
                Text("Quick start").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                HStack(spacing: 8) {
                    ForEach(presets, id: \.self) { m in
                        pill("\(m)m", color: .white.opacity(0.12)) { state.setTimer(minutes: m) }
                    }
                }
                pill("🍅 Pomodoro 25:00", color: .white.opacity(0.12)) { state.setTimer(minutes: 25) }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pill(_ title: String, icon: String? = nil, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon).font(.system(size: 10, weight: .bold)) }
                Text(title).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(color, in: Capsule())
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

// MARK: - Weather pane

struct WeatherPane: View {
    @EnvironmentObject var state: NotchState

    var body: some View {
        ZStack {
            // The sky gradient is drawn full-bleed by NotchRootView.
            if let w = state.weather {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(w.city)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                                .lineLimit(1)
                            Text("\(w.temp)\(w.unit)")
                                .font(.system(size: 40, weight: .bold))
                                .foregroundStyle(.white)
                            HStack(spacing: 10) {
                                Text(w.summary).font(.system(size: 13, weight: .medium))
                                Text("H:\(w.high)°  L:\(w.low)°").font(.system(size: 12, weight: .medium)).opacity(0.85)
                            }
                            .foregroundStyle(.white.opacity(0.9))
                        }
                        Spacer()
                        Image(systemName: w.symbol)
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 50))
                            .symbolEffect(.variableColor.iterative, options: .repeating,
                                          isActive: WeatherInfo.isPrecip(w.code))
                            .symbolEffect(.pulse, options: .repeating, isActive: w.code == 0)
                            .shadow(color: .black.opacity(0.2), radius: 6)
                            .id(w.code)
                    }

                    if !w.hourly.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(w.hourly) { HourCell(hour: $0) }
                            }
                            .padding(.vertical, 2)
                        }
                        .background(.white.opacity(0.08),
                                   in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 2)
                .padding(.top, 2)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "cloud.sun.fill")
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 26))
                    Text("Loading weather…")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { if state.weather == nil { state.refreshWeather() } }
    }

    struct HourCell: View {
        let hour: HourForecast
        var body: some View {
            VStack(spacing: 3) {
                Text(hour.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                Image(systemName: WeatherInfo.symbol(code: hour.code, isDay: hour.isDay))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 15))
                    .frame(height: 18)
                Text("\(hour.temp)°")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                HStack(spacing: 1) {
                    Image(systemName: "drop.fill").font(.system(size: 7))
                    Text("\(hour.precip)%").font(.system(size: 9, weight: .medium))
                }
                .foregroundStyle(hour.precip >= 30 ? Color(red: 0.6, green: 0.85, blue: 1.0) : .white.opacity(0.5))
            }
            .frame(width: 40)
        }
    }

    /// Sky gradient based on time of day + condition.
    static func sky(_ w: WeatherInfo) -> [Color] {
        if !w.isDay {
            return [Color(red: 0.06, green: 0.08, blue: 0.22), Color(red: 0.12, green: 0.14, blue: 0.30)]
        }
        switch w.code {
        case 0, 1:
            return [Color(red: 0.16, green: 0.52, blue: 0.93), Color(red: 0.45, green: 0.78, blue: 0.98)]
        case 2, 3, 45, 48:
            return [Color(red: 0.40, green: 0.50, blue: 0.62), Color(red: 0.58, green: 0.67, blue: 0.77)]
        case 51...67, 80...82:
            return [Color(red: 0.26, green: 0.34, blue: 0.45), Color(red: 0.40, green: 0.49, blue: 0.60)]
        case 71...77, 85, 86:
            return [Color(red: 0.55, green: 0.62, blue: 0.73), Color(red: 0.78, green: 0.83, blue: 0.90)]
        case 95...99:
            return [Color(red: 0.18, green: 0.16, blue: 0.32), Color(red: 0.34, green: 0.30, blue: 0.48)]
        default:
            return [Color(red: 0.20, green: 0.45, blue: 0.80), Color(red: 0.45, green: 0.70, blue: 0.95)]
        }
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

                Button { state.goToToday() } label: {
                    Image(systemName: "calendar")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(.red, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }.buttonStyle(.plain).help("Today")
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
                .frame(width: 19, height: 19)
                .background(background)
                .overlay(alignment: .bottom) {
                    Circle()
                        .fill(hasEvents ? (isToday ? Color.white : Color.white.opacity(0.7)) : .clear)
                        .frame(width: 3, height: 3)
                        .offset(y: 2.5)
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
    @ObservedObject private var settings = Settings.shared

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMM d"; return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Self.dayFmt.string(from: state.selectedDate))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))

            let events = state.selectedDayEvents
            if events.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "calendar.day.timeline.left")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("No events")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct CalendarRow: View {
    let event: CalEvent
    var onJoin: (() -> Void)? = nil

    static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(event.color)
                .frame(width: 8, height: 8)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(event.isPast ? 0.4 : 0.95))
                    .lineLimit(1)
                Text(event.coversWholeDay
                     ? "All day"
                     : "\(Self.timeFmt.string(from: event.start)) – \(Self.timeFmt.string(from: event.end))")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .layoutPriority(-1)
            Spacer(minLength: 0)
            if event.isNow && !event.isDayMarker {
                Text("NOW")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(.green, in: Capsule())
                    .lineLimit(1)
                    .fixedSize()
                    .layoutPriority(1)
            }
            if let onJoin {
                Button(action: onJoin) {
                    Label("Join", systemImage: "video.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.green.opacity(0.9), in: Capsule())
                }
                .buttonStyle(.plain)
                .layoutPriority(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
