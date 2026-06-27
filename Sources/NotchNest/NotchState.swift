import SwiftUI
import Combine

@MainActor
final class NotchState: ObservableObject {
    @Published var isExpanded = false
    @Published var isHoveringTab = false
    @Published var nowPlaying: NowPlaying?
    @Published var artwork: NSImage?
    @Published var artworkColor: Color?
    @Published var battery = BatteryInfo()
    @Published var shelf: [ShelfItem] = []
    @Published var tab: NotchTab = .music
    @Published var justDropped = false   // triggers a little bounce
    @Published var chargeFlash = false   // "just plugged in" celebration
    @Published var isHovering = false

    // Calendar (month view)
    @Published var monthEvents: [CalEvent] = []
    @Published var todayEvents: [CalEvent] = []
    @Published var calendarAuthorized = false
    @Published var visibleMonth: Date = NotchState.startOfMonth(Date())
    @Published var selectedDate: Date = Calendar.current.startOfDay(for: Date())

    // Bluetooth
    @Published var btDevices: [BTDevice] = []
    @Published var btPopup: BTToast?

    // Weather
    @Published var weather: WeatherInfo?

    // Generic alert toast (rain / battery)
    @Published var alert: AlertToast?
    private var alertToken = 0
    private var rainAlerted = false
    private var lowBatteryWarned = false
    private var fullNotified = false

    // HUD (volume / brightness)
    @Published var hud: HUDInfo?
    private var hudToken = 0

    // Timer
    @Published var timerRunning = false
    @Published var timerRemaining: TimeInterval = 25 * 60
    @Published var timerDuration: TimeInterval = 25 * 60
    private var timerEnd: Date?
    private var ticker: Timer?

    var timerProgress: Double {
        timerDuration > 0 ? max(0, min(1, timerRemaining / timerDuration)) : 0
    }

    let metrics: NotchMetrics
    let media = MediaController()
    let calendar = CalendarService()

    private var artworkURLLoaded: String?
    private var knownConnected: Set<String> = []
    private var lastDevices: [String: BTDevice] = [:]
    private var lowWarned: Set<String> = []
    private var btPopupToken = 0

    init(metrics: NotchMetrics) {
        self.metrics = metrics
        self.calendarAuthorized = calendar.isAuthorized
    }

    static func startOfMonth(_ date: Date) -> Date {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? date
    }

    // MARK: Media

    func refreshNowPlaying() {
        media.fetch { [weak self] np in
            guard let self else { return }
            let oldKey = self.nowPlaying?.trackKey
            self.nowPlaying = np
            if np?.trackKey != oldKey {
                self.setArtwork(nil)
                self.artworkURLLoaded = nil
                self.loadArtwork(for: np)
            }
        }
    }

    private func loadArtwork(for np: NowPlaying?) {
        guard let np else { return }
        switch np.app {
        case .music:
            // Apple Music exposes artwork as raw image data, not a URL.
            media.fetchMusicArtwork { [weak self] image in
                guard let self, self.nowPlaying?.trackKey == np.trackKey else { return }
                if let image { self.setArtwork(image) }
            }
        case .spotify:
            if let url = np.artworkURL {
                self.artworkURLLoaded = url
                self.loadArtwork(from: url)
            }
        }
    }

    /// Sets artwork and derives a tint color from it.
    private func setArtwork(_ image: NSImage?) {
        artwork = image
        guard let image else { artworkColor = nil; return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let color = ColorExtractor.vibrant(from: image)
            DispatchQueue.main.async { self?.artworkColor = color.map(Color.init) }
        }
    }

    private func loadArtwork(from urlString: String) {
        guard let url = URL(string: urlString) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async { self?.setArtwork(image) }
        }.resume()
    }

    func togglePlay() { media.playPause(app: nowPlaying?.app); bumpRefresh() }
    func next() { media.next(app: nowPlaying?.app); bumpRefresh() }
    func previous() { media.previous(app: nowPlaying?.app); bumpRefresh() }

    func seek(toFraction fraction: Double) {
        guard var np = nowPlaying, np.duration > 0 else { return }
        let seconds = fraction * np.duration
        media.seek(to: seconds, app: np.app)
        np.elapsed = seconds          // optimistic update
        nowPlaying = np
        bumpRefresh()
    }

    private func bumpRefresh() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.refreshNowPlaying()
        }
    }

    // MARK: Shelf

    func addToShelf(_ url: URL) {
        guard !shelf.contains(where: { $0.url == url }) else { return }
        shelf.insert(ShelfItem(url: url), at: 0)
        tab = .shelf
        withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { justDropped = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            withAnimation { self?.justDropped = false }
        }
    }

    func removeFromShelf(_ item: ShelfItem) {
        withAnimation(.easeInOut(duration: 0.2)) {
            shelf.removeAll { $0.id == item.id }
        }
    }

    // MARK: Battery / charging

    func updateBattery(_ newValue: BatteryInfo) {
        let wasCharging = battery.isCharging
        battery = newValue
        if newValue.isCharging && !wasCharging {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { chargeFlash = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
                withAnimation(.easeOut(duration: 0.4)) { self?.chargeFlash = false }
            }
        }

        // Low-battery warning (once, until recharged a bit).
        if !newValue.isCharging && newValue.level <= 0.20 && !lowBatteryWarned {
            lowBatteryWarned = true
            showAlert(AlertToast(symbol: "battery.25", title: "Low Battery",
                                 subtitle: "\(newValue.percent)% remaining", tint: .red))
        } else if newValue.level > 0.25 || newValue.isCharging {
            lowBatteryWarned = false
        }

        // Fully-charged notification (once per plug-in).
        if newValue.isPluggedIn && newValue.level >= 0.99 && !fullNotified {
            fullNotified = true
            showAlert(AlertToast(symbol: "battery.100.bolt", title: "Fully Charged",
                                 subtitle: "100%", tint: .green))
        } else if newValue.level < 0.95 || !newValue.isPluggedIn {
            fullNotified = false
        }
    }

    // MARK: Timer

    func setTimer(minutes: Int) {
        let d = TimeInterval(minutes * 60)
        timerDuration = d
        timerRemaining = d
        startTimer()
    }

    func startTimer() {
        if timerRemaining <= 0 { timerRemaining = timerDuration }
        timerEnd = Date().addingTimeInterval(timerRemaining)
        timerRunning = true
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickTimer() }
        }
    }

    func pauseTimer() {
        timerRunning = false
        ticker?.invalidate(); ticker = nil
        if let end = timerEnd { timerRemaining = max(0, end.timeIntervalSinceNow) }
        timerEnd = nil
    }

    func resetTimer() {
        timerRunning = false
        ticker?.invalidate(); ticker = nil
        timerEnd = nil
        timerRemaining = timerDuration
    }

    private func tickTimer() {
        guard let end = timerEnd else { return }
        timerRemaining = max(0, end.timeIntervalSinceNow)
        if timerRemaining <= 0 { finishTimer() }
    }

    private func finishTimer() {
        ticker?.invalidate(); ticker = nil
        timerEnd = nil
        timerRunning = false
        timerRemaining = 0
        NSSound(named: "Glass")?.play()
        showAlert(AlertToast(symbol: "timer", title: "Timer Done",
                             subtitle: "\(Int(timerDuration / 60)) min finished", tint: .orange))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            self.timerRemaining = self.timerDuration
        }
    }

    func showAlert(_ toast: AlertToast) {
        alertToken += 1
        let token = alertToken
        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { alert = toast }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            guard let self, self.alertToken == token else { return }
            withAnimation(.easeInOut(duration: 0.35)) { self.alert = nil }
        }
    }

    // MARK: Calendar

    var disableLiveRefresh = false   // snapshot/testing only

    func refreshCalendar() {
        if disableLiveRefresh { return }
        calendarAuthorized = calendar.isAuthorized
        guard calendarAuthorized else { return }
        let cal = Calendar.current
        let start = visibleMonth
        let end = cal.date(byAdding: .month, value: 1, to: start) ?? start
        // Fetch off the main thread so it never janks the expand animation.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let month = self.calendar.events(from: start, to: end)
            let today = self.calendar.todayEvents()
            DispatchQueue.main.async {
                if month != self.monthEvents { self.monthEvents = month }
                if today != self.todayEvents { self.todayEvents = today }
            }
        }
    }

    /// Soonest timed event today that hasn't ended yet.
    var nextEvent: CalEvent? {
        let now = Date()
        return todayEvents
            .filter { !$0.isAllDay && $0.end > now }
            .min { $0.start < $1.start }
    }

    /// The next event if it's ongoing or starts within the hour (for the pill).
    var imminentEvent: CalEvent? {
        guard let ev = nextEvent else { return nil }
        return ev.start.timeIntervalSinceNow <= 3600 ? ev : nil
    }

    func join(_ event: CalEvent) {
        guard let url = event.videoURL else { return }
        NSWorkspace.shared.open(url)
    }

    func changeMonth(by delta: Int) {
        let cal = Calendar.current
        if let m = cal.date(byAdding: .month, value: delta, to: visibleMonth) {
            visibleMonth = NotchState.startOfMonth(m)
            refreshCalendar()
        }
    }

    func goToToday() {
        visibleMonth = NotchState.startOfMonth(Date())
        selectedDate = Calendar.current.startOfDay(for: Date())
        refreshCalendar()
    }

    func select(_ date: Date) {
        selectedDate = Calendar.current.startOfDay(for: date)
    }

    /// Events on the currently selected day.
    var selectedDayEvents: [CalEvent] {
        let cal = Calendar.current
        return monthEvents.filter { cal.isDate($0.start, inSameDayAs: selectedDate) }
    }

    /// Days (in the visible month) that have at least one event.
    var daysWithEvents: Set<Int> {
        let cal = Calendar.current
        return Set(monthEvents.compactMap { ev -> Int? in
            guard cal.isDate(ev.start, equalTo: visibleMonth, toGranularity: .month) else { return nil }
            return cal.component(.day, from: ev.start)
        })
    }

    func requestCalendarAccess() {
        calendar.requestAccess { [weak self] granted in
            self?.calendarAuthorized = granted
            if granted { self?.refreshCalendar() }
        }
    }

    // MARK: Bluetooth

    func updateBluetooth(_ devices: [BTDevice]) {
        btDevices = devices
        let nowConnected = Set(devices.map(\.address))
        for d in devices { lastDevices[d.address] = d }

        let newly = nowConnected.subtracting(knownConnected)
        let gone = knownConnected.subtracting(nowConnected)

        // Skip toasts on the very first poll (devices already connected at launch).
        if !knownConnected.isEmpty {
            if let addr = newly.first, let device = devices.first(where: { $0.address == addr }) {
                showToast(BTToast(device: device, kind: .connected))
            } else if let addr = gone.first, let device = lastDevices[addr] {
                lowWarned.remove(addr)
                showToast(BTToast(device: device, kind: .disconnected))
            }
        }

        // Low-battery warning for connected devices (once per drop below threshold).
        for d in devices {
            guard let pct = d.primaryBattery else { continue }
            if pct <= 20 && !lowWarned.contains(d.address) {
                lowWarned.insert(d.address)
                if btPopup == nil { showToast(BTToast(device: d, kind: .lowBattery)) }
            } else if pct > 25 {
                lowWarned.remove(d.address)
            }
        }

        knownConnected = nowConnected
    }

    private func showToast(_ toast: BTToast) {
        btPopupToken += 1
        let token = btPopupToken
        // Small banner only — don't force the full expanded card open.
        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
            btPopup = toast
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
            guard let self, self.btPopupToken == token else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                self.btPopup = nil
            }
        }
    }

    // MARK: AirDrop

    func airDrop(_ urls: [URL]) {
        AirDropService.send(urls)
    }

    // MARK: Weather

    func refreshWeather() {
        WeatherService.fetch { [weak self] info in
            guard let self, let info else { return }
            self.weather = info
            self.checkRainAlert(info)
        }
    }

    /// Alert when it's dry now but rain looks likely in the next few hours.
    private func checkRainAlert(_ w: WeatherInfo) {
        let dryNow = !WeatherInfo.isPrecip(w.code)
        let soon = w.hourly.prefix(3).contains { $0.precip >= 50 || WeatherInfo.isPrecip($0.code) }
        if dryNow && soon && !rainAlerted {
            rainAlerted = true
            showAlert(AlertToast(symbol: "cloud.rain.fill", title: "Rain Likely Soon",
                                 subtitle: "Showers expected within a few hours",
                                 tint: Color(red: 0.5, green: 0.8, blue: 1.0)))
        } else if !soon {
            rainAlerted = false
        }
    }

    // MARK: HUD

    /// Show a transient volume/brightness HUD in the notch.
    func showHUD(_ kind: HUDInfo.Kind, value: Double) {
        hudToken += 1
        let token = hudToken
        let info = HUDInfo(kind: kind, value: min(max(value, 0), 1))
        if hud != info {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { hud = info }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            guard let self, self.hudToken == token else { return }
            withAnimation(.easeOut(duration: 0.3)) { self.hud = nil }
        }
    }
}
