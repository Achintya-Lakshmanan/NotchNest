import SwiftUI
import Combine

@MainActor
final class NotchState: ObservableObject {
    @Published var isExpanded = false
    @Published var showingPreferences = false
    @Published var showingMenuBarApps = false
    @Published var nowPlaying: NowPlaying? {
        didSet { updateMusicPresentation(wasPlaying: oldValue?.isPlaying == true) }
    }
    @Published var artwork: NSImage?
    @Published var artworkColor: Color?
    @Published private(set) var musicPresentationActive = false
    private let musicIdleDelay: Duration
    private var musicIdleExpiry: Task<Void, Never>?
    private var musicPresentationGeneration = 0
    @Published var battery = BatteryInfo()
    @Published var shelf: [ShelfItem] = []
    @Published var downloads: [DownloadItem] = []
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
    /// Deadline-like events over the next two weeks (assignments, exams, registrar dates).
    @Published var deadlines: [Deadline] = []
    @Published var showingDeadlines = false
    private var classHeadsUpShown: Set<String> = []

    // Music extras
    /// When `nowPlaying.elapsed` was read, so lyrics can follow playback between polls.
    private(set) var elapsedSampledAt = Date()
    @Published var showingLyrics = false
    @Published private(set) var lyrics: Lyrics?
    @Published private(set) var lyricsLoading = false
    private var lyricsTrackKey: String?

    // Claude limit alerts
    private var claudeLowAlerted: Set<String> = []
    private var claudeResetTask: Task<Void, Never>?
    private var usageCancellable: AnyCancellable?

    // Bluetooth
    @Published var btDevices: [BTDevice] = []
    @Published var btPopup: BTToast?

    // Weather
    @Published var weather: WeatherInfo?

    // Generic alert toast (rain / battery)
    @Published var alert: AlertToast?
    private var alertToken = 0
    private var alertQueue: [PendingAlert] = []
    private var visibleAlert: PendingAlert?
    private var alertShownAt: Date?
    private var visibleAlertKey: String? { visibleAlert?.key }
    private var presentationCancellables: Set<AnyCancellable> = []
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
    @Published private(set) var pomodoro: PomodoroState?
    /// Snapshot/testing only.
    func setPomodoroForPreview(_ value: PomodoroState?) { pomodoro = value }
    private var timerEnd: Date?
    private var ticker: Timer?

    var timerProgress: Double {
        timerDuration > 0 ? max(0, min(1, timerRemaining / timerDuration)) : 0
    }

    @Published var metrics: NotchMetrics
    var presentationSize: CGSize {
        if isExpanded { return metrics.expandedSize }
        if hud != nil { return metrics.hudSize }
        if btPopup != nil || alert != nil { return metrics.toastSize }
        return metrics.compactSize
    }
    let media = MediaController()
    let calendar = CalendarService()
    let codexUsage: CodexUsageService
    let claudeUsage: ClaudeUsageService
    let reminders: ReminderService
    let focusMonitor = FocusMonitor()
    let menuBarApps: MenuBarAppsService

    private var artworkURLLoaded: String?
    private var lastDevices: [String: BTDevice] = [:]
    private var lowWarned: Set<String> = []
    private var btPopupToken = 0

    init(metrics: NotchMetrics, codexUsage: CodexUsageService? = nil, reminders: ReminderService? = nil,
         musicIdleDelay: Duration = .seconds(30), menuBarApps: MenuBarAppsService? = nil,
         claudeUsage: ClaudeUsageService? = nil) {
        self.metrics = metrics
        self.musicIdleDelay = musicIdleDelay
        self.codexUsage = codexUsage ?? CodexUsageService()
        self.claudeUsage = claudeUsage ?? ClaudeUsageService()
        self.reminders = reminders ?? ReminderService()
        self.menuBarApps = menuBarApps ?? MenuBarAppsService()
        self.calendarAuthorized = calendar.isAuthorized
        // A queued popup goes up as soon as whatever was covering it goes away.
        Publishers.Merge3($isExpanded.map { _ in () }, $hud.map { _ in () }, $btPopup.map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in MainActor.assumeIsolated { self?.presentNextAlert() } }
            .store(in: &presentationCancellables)
        // Hovering a popup opens the card, which hides it. Put it back at the
        // front of the queue (with its full time) instead of losing it.
        $isExpanded.removeDuplicates().filter { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.suspendVisibleAlert() } }
            .store(in: &presentationCancellables)
        usageCancellable = self.claudeUsage.$usage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] usage in MainActor.assumeIsolated { self?.checkClaudeAlerts(usage) } }
    }

    /// Keep the timer, shelf, and selected tab, but never replay an old HUD or
    /// connection toast after coming back from a TV-only/mirrored session.
    func dismissTransientPresentation() {
        hudToken += 1
        btPopupToken += 1
        alertToken += 1
        hud = nil
        btPopup = nil
        alert = nil
        alertQueue.removeAll()
        visibleAlert = nil
        chargeFlash = false
        isHovering = false
        isExpanded = false
        showingPreferences = false
        showingMenuBarApps = false
        showingLyrics = false
    }

    static func startOfMonth(_ date: Date) -> Date {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? date
    }

    // MARK: Media

    var showsCompactMeeting: Bool {
        let settings = Settings.shared
        return settings.showMeetingCountdown && settings.isEnabled(.calendar) && imminentEvent != nil
    }

    /// Music can keep reporting its last track for days. Keep that cached data
    /// for resuming playback, but only present playing or recently paused music.
    var displayedNowPlaying: NowPlaying? {
        musicPresentationActive ? nowPlaying : nil
    }

    private func updateMusicPresentation(wasPlaying: Bool) {
        if nowPlaying?.isPlaying == true {
            guard !wasPlaying || !musicPresentationActive else { return }
            cancelMusicIdleExpiry()
            musicPresentationActive = true
        } else if nowPlaying == nil {
            cancelMusicIdleExpiry()
            musicPresentationActive = false
        } else if wasPlaying {
            // One expiry per pause, not a repeating timer. Metadata / seek updates
            // while paused must not keep extending the overview's lifetime.
            cancelMusicIdleExpiry()
            let generation = musicPresentationGeneration
            let delay = musicIdleDelay
            musicIdleExpiry = Task { [weak self] in
                do { try await Task.sleep(for: delay) } catch { return }
                guard !Task.isCancelled, let self,
                      self.musicPresentationGeneration == generation,
                      self.nowPlaying?.isPlaying != true else { return }
                self.musicPresentationActive = false
                self.musicIdleExpiry = nil
            }
        }
        // Launching while Music is already paused starts idle. Retain cached
        // artwork for resume, but do not display it as current playback.
    }

    private func cancelMusicIdleExpiry() {
        musicPresentationGeneration += 1
        musicIdleExpiry?.cancel()
        musicIdleExpiry = nil
    }

    func refreshNowPlaying() {
        media.fetch { [weak self] np in
            guard let self else { return }
            let oldKey = self.nowPlaying?.trackKey
            // Skip @Published churn when nothing meaningful changed (sub-second elapsed noise).
            if let np, let old = self.nowPlaying,
               np.trackKey == old.trackKey,
               np.isPlaying == old.isPlaying,
               np.app == old.app,
               abs(np.elapsed - old.elapsed) < 0.4,
               abs(np.duration - old.duration) < 0.01,
               np.isFavorited == old.isFavorited {
                return
            }
            if np == nil, self.nowPlaying == nil { return }
            self.elapsedSampledAt = Date()
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
        Task { [weak self] in
            let color = await Task.detached(priority: .userInitiated) {
                ColorExtractor.vibrant(from: image).map(Color.init)
            }.value
            self?.artworkColor = color
        }
    }

    private func loadArtwork(from urlString: String) {
        guard let url = URL(string: urlString) else { return }
        Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = NSImage(data: data) else { return }
            // Drop stale responses when the track (URL) already changed.
            guard let self, self.artworkURLLoaded == urlString else { return }
            self.setArtwork(image)
        }
    }

    func togglePlay() { media.playPause(app: nowPlaying?.app); bumpRefresh() }
    func next() { media.next(app: nowPlaying?.app); bumpRefresh() }
    func previous() { media.previous(app: nowPlaying?.app); bumpRefresh() }

    func seek(toFraction fraction: Double) {
        guard var np = nowPlaying, np.duration > 0 else { return }
        let seconds = fraction * np.duration
        media.seek(to: seconds, app: np.app)
        np.elapsed = seconds          // optimistic update
        elapsedSampledAt = Date()
        nowPlaying = np
        bumpRefresh()
    }

    /// Playback position now, extrapolated from the last poll while playing.
    func estimatedElapsed(at now: Date = Date()) -> Double {
        guard let np = nowPlaying else { return 0 }
        let drift = np.isPlaying ? now.timeIntervalSince(elapsedSampledAt) : 0
        return min(np.elapsed + max(0, drift), np.duration > 0 ? np.duration : .infinity)
    }

    func toggleFavorite() {
        guard var np = nowPlaying, np.app == .music, let current = np.isFavorited else { return }
        media.setFavorite(!current)
        np.isFavorited = !current        // optimistic; the next poll confirms
        nowPlaying = np
        bumpRefresh()
    }

    func toggleLyrics() {
        showingLyrics.toggle()
    }

    /// Called by the visible lyrics view (via `.task(id:)`), so nothing is sent
    /// to LRCLIB while lyrics are closed or the notch is collapsed.
    /// Found/not-found answers are cached per track; network errors are retried.
    func loadLyricsIfNeeded() async {
        guard let np = nowPlaying, !disableLiveRefresh, Settings.shared.lyricsEnabled else { return }
        if lyricsTrackKey == np.trackKey, lyrics != nil { return }
        lyricsTrackKey = np.trackKey
        lyrics = nil
        lyricsLoading = true
        let result = await LyricsService.fetch(np)
        guard !Task.isCancelled, lyricsTrackKey == np.trackKey else { return }
        lyricsLoading = false
        switch result {
        case .success(let value): lyrics = value
        case .failure:
            lyrics = .failed
            lyricsTrackKey = nil      // next open (or next track) tries again
        }
    }

    /// Snapshot/testing only.
    func setLyricsForPreview(_ value: Lyrics?) {
        lyricsTrackKey = nowPlaying?.trackKey
        lyrics = value
        lyricsLoading = false
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

    func clearShelf() {
        withAnimation(.easeInOut(duration: 0.2)) { shelf.removeAll() }
    }

    func removeFromShelf(_ item: ShelfItem) {
        withAnimation(.easeInOut(duration: 0.2)) {
            shelf.removeAll { $0.id == item.id }
        }
    }

    // MARK: Battery / charging

    func updateBattery(_ newValue: BatteryInfo) {
        guard newValue != battery else { return }
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
        pomodoro = nil
        let d = TimeInterval(minutes * 60)
        timerDuration = d
        timerRemaining = d
        startTimer()
    }

    /// Custom length via the −/+ stepper (only while stopped). 1–180 minutes.
    func adjustTimer(byMinutes delta: Int) {
        guard !timerRunning else { return }
        pomodoro = nil
        let minutes = min(180, max(1, Int((timerDuration / 60).rounded()) + delta))
        timerDuration = TimeInterval(minutes * 60)
        timerRemaining = timerDuration
    }

    /// 25 min focus → 5 min break, with a 15 min break after every 4th round.
    func startPomodoro() {
        pomodoro = PomodoroState(phase: .focus, round: 1)
        beginPomodoroPhase()
    }

    private func beginPomodoroPhase() {
        guard let p = pomodoro else { return }
        timerDuration = p.phase.duration(round: p.round)
        timerRemaining = timerDuration
        startTimer()
    }

    func startTimer() {
        if timerRemaining <= 0 { timerRemaining = timerDuration }
        timerEnd = Date().addingTimeInterval(timerRemaining)
        timerRunning = true
        ticker?.invalidate()
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickTimer() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    func pauseTimer() {
        timerRunning = false
        ticker?.invalidate(); ticker = nil
        if let end = timerEnd { timerRemaining = max(0, end.timeIntervalSinceNow) }
        timerEnd = nil
    }

    func resetTimer() {
        pomodoro = nil
        timerRunning = false
        ticker?.invalidate(); ticker = nil
        timerEnd = nil
        timerRemaining = timerDuration
    }

    private func tickTimer() {
        guard let end = timerEnd else { return }
        let remaining = max(0, end.timeIntervalSinceNow)
        if remaining <= 0 {
            finishTimer()
            return
        }
        // Coalesce @Published churn: UI shows whole seconds; skip sub-second noise.
        if Int(remaining.rounded()) != Int(timerRemaining.rounded()) {
            timerRemaining = remaining
        }
    }

    private func finishTimer() {
        ticker?.invalidate(); ticker = nil
        timerEnd = nil
        timerRunning = false
        timerRemaining = 0
        NSSound(named: "Glass")?.play()
        if var p = pomodoro {
            // Move to the next phase and keep going.
            if p.phase == .focus {
                p.phase = .rest
                pomodoro = p
                showAlert(AlertToast(symbol: "cup.and.saucer.fill", title: "Focus round \(p.round) done",
                                     subtitle: "Take a \(Int(p.phase.duration(round: p.round) / 60)) min break",
                                     tint: .green), duration: 5)
            } else {
                p.phase = .focus
                p.round += 1
                pomodoro = p
                showAlert(AlertToast(symbol: "brain.head.profile", title: "Break over",
                                     subtitle: "Focus round \(p.round) · 25 min", tint: .orange), duration: 5)
            }
            beginPomodoroPhase()
            return
        }
        showAlert(AlertToast(symbol: "timer", title: "Timer Done",
                             subtitle: "\(Int(timerDuration / 60)) min finished", tint: .orange))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            self.timerRemaining = self.timerDuration
        }
    }

    /// Queues a popup. It appears once the notch is collapsed and no HUD or
    /// Bluetooth popup is showing; its countdown starts only when it is visible.
    /// - key: status popups (Caps Lock, Focus) replace an older one with the same key.
    /// - maxWait: drop the popup if it couldn't be shown within this time.
    /// - update: rebuilds the toast at the moment it is shown (e.g. "Starts in 3 min").
    func showAlert(_ toast: AlertToast, duration: TimeInterval = 4, key: String? = nil,
                   maxWait: TimeInterval = 600, update: (() -> AlertToast)? = nil) {
        if let key {
            alertQueue.removeAll { $0.key == key }
            if alert != nil, visibleAlertKey == key {
                display(PendingAlert(toast: toast, duration: duration, key: key,
                                     expires: .distantFuture, update: update))
                return
            }
        }
        alertQueue.append(PendingAlert(toast: toast, duration: duration, key: key,
                                       expires: Date().addingTimeInterval(maxWait), update: update))
        presentNextAlert()
    }

    private struct PendingAlert {
        var toast: AlertToast
        var duration: TimeInterval
        var key: String?
        var expires: Date
        var update: (() -> AlertToast)?
    }

    private func presentNextAlert() {
        guard alert == nil, !isExpanded, hud == nil, btPopup == nil else { return }
        let now = Date()
        alertQueue.removeAll { $0.expires < now }
        guard !alertQueue.isEmpty else { return }
        display(alertQueue.removeFirst())
    }

    private func display(_ pending: PendingAlert) {
        alertToken += 1
        let token = alertToken
        visibleAlert = pending
        alertShownAt = Date()
        let toast = pending.update?() ?? pending.toast
        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { alert = toast }
        DispatchQueue.main.asyncAfter(deadline: .now() + pending.duration) { [weak self] in
            guard let self, self.alertToken == token else { return }
            withAnimation(.easeInOut(duration: 0.35)) { self.alert = nil }
            self.visibleAlert = nil
            // Let the card animate out before the next one appears.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in self?.presentNextAlert() }
        }
    }

    /// The card opened over a visible popup: stop its countdown and re-queue it
    /// first, so it comes back with its full duration when the card closes.
    func suspendVisibleAlert() {
        guard isExpanded, alert != nil, var pending = visibleAlert else { return }
        alertToken += 1
        alert = nil
        visibleAlert = nil
        // Already on screen long enough to be read: don't replay it on every hover.
        if let shown = alertShownAt, Date().timeIntervalSince(shown) >= 1.5 { return }
        // Re-queued popups keep their own deadline; a status popup that was
        // already showing gets a short grace period.
        if pending.expires == .distantFuture { pending.expires = Date().addingTimeInterval(60) }
        alertQueue.insert(pending, at: 0)
    }

    /// Snapshot/testing only.
    var pendingAlertCount: Int { alertQueue.count }

    // MARK: Calendar

    var disableLiveRefresh = false   // snapshot/testing only

    func refreshCalendar() {
        if disableLiveRefresh { return }
        calendarAuthorized = calendar.isAuthorized
        guard calendarAuthorized else { return }
        let cal = Calendar.current
        let start = visibleMonth
        let end = cal.date(byAdding: .month, value: 1, to: start) ?? start
        // Capture service on MainActor, then query EventKit off-main (store is thread-safe for reads).
        let service = calendar
        let hidden = Settings.shared.hiddenCalendars
        let dayStart = cal.startOfDay(for: Date())
        let horizon = cal.date(byAdding: .day, value: 15, to: dayStart) ?? dayStart
        Task.detached {
            let month = service.events(from: start, to: end, hiding: hidden)
            // One query covers today and the deadline horizon.
            let ahead = service.events(from: dayStart, to: horizon, hiding: hidden)
            let today = ahead.filter { $0.occurs(on: dayStart) }
            let upcoming = Deadline.from(ahead)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.applyCalendarResults(month: month, for: start, today: today, deadlines: upcoming)
            }
        }
    }

    /// Today and deadlines don't depend on the month being browsed, so they always
    /// update (class mode keeps working after you look at next month). Only the
    /// grid drops a response for a month you've since navigated away from.
    func applyCalendarResults(month: [CalEvent], for monthStart: Date, today: [CalEvent], deadlines upcoming: [Deadline]) {
        if upcoming != deadlines { deadlines = upcoming }
        if today != todayEvents { todayEvents = today }
        guard visibleMonth == monthStart else { return }
        if month != monthEvents { monthEvents = month }
    }

    /// Timed, busy events today (classes and meetings), not day markers or free holds.
    private func classLike(now: Date) -> [CalEvent] {
        todayEvents.filter { !$0.isDayMarker && !$0.isFree && $0.end > now }
    }

    /// Soonest event that hasn't started yet, even while another one is running.
    func upcomingEvent(now: Date = Date()) -> CalEvent? {
        classLike(now: now).filter { $0.start > now }.min { $0.start < $1.start }
    }

    /// What the collapsed pill shows: a class starting within 10 minutes wins,
    /// then the live event ending soonest, then anything starting within the hour.
    func imminentEvent(now: Date = Date()) -> CalEvent? {
        let events = classLike(now: now)
        let upcoming = events.filter { $0.start > now }.min { $0.start < $1.start }
        if let upcoming, upcoming.start.timeIntervalSince(now) <= 10 * 60 { return upcoming }
        if let live = events.filter({ $0.start <= now }).min(by: { $0.end < $1.end }) { return live }
        if let upcoming, upcoming.start.timeIntervalSince(now) <= 3600 { return upcoming }
        return nil
    }

    var imminentEvent: CalEvent? { imminentEvent() }

    /// One heads-up per class or meeting, about 10 minutes before it starts.
    func checkClassHeadsUp(now: Date = Date()) {
        guard Settings.shared.showMeetingCountdown, Settings.shared.isEnabled(.calendar),
              let event = upcomingEvent(now: now),
              event.start.timeIntervalSince(now) <= 10 * 60,
              !classHeadsUpShown.contains(event.id) else { return }
        classHeadsUpShown.insert(event.id)
        let start = event.start
        let place = event.location.map { " · \($0)" } ?? ""
        let symbol = event.videoURL != nil ? "video.fill" : "graduationcap.fill"
        func toast() -> AlertToast {
            let minutes = max(1, Int(ceil(start.timeIntervalSinceNow / 60)))
            return AlertToast(symbol: symbol, title: event.title,
                              subtitle: "Starts in \(minutes) min\(place)", tint: event.color)
        }
        // Built when shown, and dropped if it couldn't be shown before class starts.
        showAlert(toast(), duration: 6, maxWait: max(0, start.timeIntervalSince(now)), update: toast)
    }

    // MARK: Claude limit alerts

    /// Low-limit popups once per window, plus a popup when a nearly used
    /// five-hour window resets. Fires from whatever refresh produced `usage`.
    func checkClaudeAlerts(_ usage: WeeklyUsage?, now: Date = Date()) {
        // A failed refresh (nil) keeps the reset popup already scheduled.
        guard let usage else { return }
        claudeResetTask?.cancel()
        claudeResetTask = nil
        guard Settings.shared.claudeLimitAlerts, Settings.shared.showClaudeUsage else { return }

        // Windows are identified by their reset time (to the minute). Without
        // one we can't tell windows apart, so we don't alert.
        if let session = usage.session, !session.resetIsDue(at: now), let sessionReset = session.resetsAt {
            let key = "5h-\(Int(sessionReset.timeIntervalSince1970 / 60))"
            if session.remainingPercent <= 10, claudeLowAlerted.insert(key).inserted {
                let reset = session.resetsAt.map { " · resets in " + WeeklyUsage.countdown(to: $0, at: now) } ?? ""
                showAlert(AlertToast(symbol: "hourglass.bottomhalf.filled",
                                     title: "Claude 5-hour limit: \(session.remainingLabel) left",
                                     subtitle: "Running low\(reset)", tint: .orange), duration: 6)
            }
            // Announce the reset only if the window was mostly used.
            if session.remainingPercent <= 25, let resetsAt = session.resetsAt {
                let delay = resetsAt.timeIntervalSince(now)
                claudeResetTask = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(delay + 5)) } catch { return }
                    guard let self, !Task.isCancelled,
                          Settings.shared.claudeLimitAlerts, Settings.shared.showClaudeUsage else { return }
                    self.showAlert(AlertToast(symbol: "arrow.clockwise.circle.fill",
                                              title: "Claude 5-hour limit reset",
                                              subtitle: "Your session allowance is full again",
                                              tint: Color(red: 0.94, green: 0.65, blue: 0.49)), duration: 5)
                }
            }
        }
        if !usage.resetIsDue(at: now), usage.remainingPercent <= 10, let weeklyReset = usage.resetsAt {
            let key = "7d-\(Int(weeklyReset.timeIntervalSince1970 / 60))"
            if claudeLowAlerted.insert(key).inserted {
                showAlert(AlertToast(symbol: "exclamationmark.triangle.fill",
                                     title: "Claude weekly limit: \(usage.remainingLabel) left",
                                     subtitle: "Resets in " + usage.countdown(at: now), tint: .orange), duration: 6)
            }
        }
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

    func goToToday(now: Date = Date()) {
        visibleMonth = NotchState.startOfMonth(now)
        selectedDate = Calendar.current.startOfDay(for: now)
        refreshCalendar()
    }

    func select(_ date: Date) {
        selectedDate = Calendar.current.startOfDay(for: date)
        // Picking a day means "show me that day", even from the deadlines list.
        showingDeadlines = false
        // A deadline next month: move the grid there too.
        let month = NotchState.startOfMonth(date)
        if month != visibleMonth {
            visibleMonth = month
            refreshCalendar()
        }
    }

    /// Events on the currently selected day, including multi-day events that span it.
    var selectedDayEvents: [CalEvent] {
        monthEvents.filter { $0.occurs(on: selectedDate) }
    }

    /// Days (in the visible month) that have at least one event.
    var daysWithEvents: Set<Int> {
        let cal = Calendar.current
        guard let range = cal.range(of: .day, in: .month, for: visibleMonth) else { return [] }
        return Set(range.filter { day in
            guard let date = cal.date(byAdding: .day, value: day - 1, to: visibleMonth) else { return false }
            return monthEvents.contains { $0.occurs(on: date) }
        })
    }

    func requestCalendarAccess() {
        calendar.requestAccess { [weak self] granted in
            self?.calendarAuthorized = granted
            if granted { self?.refreshCalendar() }
        }
    }

    // MARK: Bluetooth

    /// Updates device list and battery from `system_profiler` polling (not connect/disconnect toasts).
    /// IOBluetooth `eventConnected` is the source of truth for which devices are shown.
    func updateBluetooth(_ devices: [BTDevice], eventConnected: Set<String>) {
        for d in devices {
            lastDevices[d.normalizedAddress] = d
        }

        guard !eventConnected.isEmpty else {
            if !btDevices.isEmpty { btDevices = [] }
            return
        }

        let effective = eventConnected.compactMap { normalizedAddr -> BTDevice? in
            devices.first { $0.normalizedAddress == normalizedAddr }
                ?? lastDevices[normalizedAddr]
                ?? btDevices.first { $0.normalizedAddress == normalizedAddr }
        }
        if effective != btDevices {
            btDevices = effective
        }

        for d in effective {
            guard let pct = d.primaryBattery else { continue }
            let key = d.normalizedAddress
            if pct <= 20 && !lowWarned.contains(key) {
                lowWarned.insert(key)
                if btPopup == nil { showToast(BTToast(device: d, kind: .lowBattery)) }
            } else if pct > 25 {
                lowWarned.remove(key)
            }
        }
    }

    func bluetoothDidConnect(name: String, address: String) {
        let key = BTDevice.normalizeAddress(address)
        let device = lastDevices[key] ?? BTDevice(
            address: address, name: name,
            batteryMain: nil, batteryLeft: nil, batteryRight: nil, batteryCase: nil, minorType: nil
        )
        if !btDevices.contains(where: { $0.normalizedAddress == key }) {
            btDevices.append(device)
        }
        showToast(BTToast(device: device, kind: .connected))
    }

    func bluetoothDidDisconnect(name: String, address: String) {
        let key = BTDevice.normalizeAddress(address)
        btDevices.removeAll { $0.normalizedAddress == key }
        let device = lastDevices[key] ?? BTDevice(
            address: address, name: name,
            batteryMain: nil, batteryLeft: nil, batteryRight: nil, batteryCase: nil, minorType: nil
        )
        lowWarned.remove(key)
        showToast(BTToast(device: device, kind: .disconnected))
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

    // MARK: Downloads

    func updateDownloads(_ items: [DownloadItem]) {
        guard items != downloads else { return }
        withAnimation(.easeInOut(duration: 0.2)) { downloads = items }
    }

    func downloadDidFinish(name: String) {
        showAlert(AlertToast(
            symbol: "arrow.down.circle.fill",
            title: "Download Complete",
            subtitle: name,
            tint: Color(red: 0.35, green: 0.75, blue: 1.0)
        ))
    }

    // MARK: Weather

    func refreshWeather() {
        WeatherService.fetch { [weak self] info in
            guard let self, let info else { return }
            if self.weather != info {
                self.weather = info
            }
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
