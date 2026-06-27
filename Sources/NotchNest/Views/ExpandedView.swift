import SwiftUI
import UniformTypeIdentifiers

struct ExpandedView: View {
    @EnvironmentObject var state: NotchState
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        VStack(spacing: 8) {
            topBar
            Divider().overlay(.white.opacity(0.08))
            Group {
                switch state.tab {
                case .music: MusicPane()
                case .calendar: CalendarPane()
                case .weather: WeatherPane()
                case .shelf: ShelfPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Push content below the physical notch so the tab bar is visible.
        .padding(.top, max(8, state.metrics.notchHeight))
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
        .foregroundStyle(.white)
        .onAppear(perform: ensureValidTab)
        .onChange(of: settings.disabledTabs) { _ in ensureValidTab() }
    }

    private func ensureValidTab() {
        if !settings.isEnabled(state.tab), let first = settings.enabledTabs.first {
            state.tab = first
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                Text(Self.timeFormatter.string(from: Date()))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .monospacedDigit()
            }

            Spacer()

            // Tab switcher (only enabled tabs)
            HStack(spacing: 4) {
                ForEach(settings.enabledTabs, id: \.self) { tab in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { state.tab = tab }
                    } label: {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(state.tab == tab ? .white : .white.opacity(0.45))
                            .frame(width: 26, height: 20)
                            .background(state.tab == tab ? .white.opacity(0.16) : .clear,
                                       in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    NotificationCenter.default.post(name: .openPreferences, object: nil)
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(width: 26, height: 20)
                }
                .buttonStyle(.plain)
                .help("Preferences")
            }

            Spacer()

            BatteryCluster()
        }
    }

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE  h:mm a"
        return f
    }()
}

// MARK: - Music pane

struct MusicPane: View {
    @EnvironmentObject var state: NotchState

    var body: some View {
        if let np = state.nowPlaying {
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
                        OutputDeviceMenu()
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

// MARK: - Weather pane

struct WeatherPane: View {
    @EnvironmentObject var state: NotchState

    var body: some View {
        ZStack {
            if let w = state.weather {
                LinearGradient(colors: Self.sky(w), startPoint: .top, endPoint: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(w.city)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                        Text("\(w.temp)\(w.unit)")
                            .font(.system(size: 46, weight: .bold))
                            .foregroundStyle(.white)
                        Text(w.summary)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                        HStack(spacing: 10) {
                            Label("\(w.high)°", systemImage: "arrow.up")
                            Label("\(w.low)°", systemImage: "arrow.down")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.top, 2)
                    }
                    Spacer()
                    Image(systemName: w.symbol)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 60))
                        .symbolEffect(.variableColor.iterative, options: .repeating,
                                      isActive: Self.isPrecip(w.code))
                        .symbolEffect(.pulse, options: .repeating,
                                      isActive: w.code == 0)
                        .shadow(color: .black.opacity(0.2), radius: 6)
                        .id(w.code)   // re-evaluate effects when condition changes
                }
                .padding(20)
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

    static func isPrecip(_ code: Int) -> Bool {
        switch code {
        case 51...67, 71...77, 80...86, 95...99: return true
        default: return false
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
        .onAppear { state.refreshCalendar() }
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

    var body: some View {
        VStack(spacing: 5) {
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
                        .frame(width: 24, height: 24)
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
                    if let day { DayCell(day: day) } else { Color.clear.frame(height: 26) }
                }
            }
            Spacer(minLength: 0)
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
            VStack(spacing: 1) {
                Text("\(day)")
                    .font(.system(size: 12, weight: isSelected || isToday ? .bold : .regular))
                    .foregroundStyle(foreground)
                    .frame(width: 24, height: 24)
                    .background(background)
                Circle()
                    .fill(hasEvents ? Color.white.opacity(0.7) : .clear)
                    .frame(width: 3, height: 3)
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
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
                Text(event.isAllDay
                     ? "All day"
                     : "\(Self.timeFmt.string(from: event.start)) – \(Self.timeFmt.string(from: event.end))")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer(minLength: 0)
            if event.isNow {
                Text("NOW")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(.green, in: Capsule())
            }
            if let onJoin {
                Button(action: onJoin) {
                    Label("Join", systemImage: "video.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.green.opacity(0.9), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
