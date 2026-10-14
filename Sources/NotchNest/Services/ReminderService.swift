import AppKit
import Combine
import EventKit

struct ReminderInfo: Equatable, Identifiable {
    let id: String
    let title: String
    let listName: String
    let due: Date
    let dateOnly: Bool
    let colorComponents: [CGFloat]

    static func dueDate(from components: DateComponents, calendar fallback: Calendar = .current) -> (Date, Bool)? {
        guard components.year != nil, components.month != nil, components.day != nil else { return nil }
        var calendar = components.calendar ?? fallback
        if let zone = components.timeZone { calendar.timeZone = zone }
        let dateOnly = components.hour == nil && components.minute == nil && components.second == nil
        var normalized = components
        if dateOnly { normalized.hour = 0; normalized.minute = 0; normalized.second = 0 }
        guard let date = calendar.date(from: normalized) else { return nil }
        return (date, dateOnly)
    }

    func isOverdue(at now: Date, calendar: Calendar = .current) -> Bool {
        // A date-only reminder is due throughout its day, not overdue at midnight.
        dateOnly ? calendar.startOfDay(for: due) < calendar.startOfDay(for: now) : due < now
    }

    func dueLabel(at now: Date, calendar: Calendar = .current) -> String {
        if isOverdue(at: now, calendar: calendar) { return "Overdue" }
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        if dateOnly {
            if calendar.isDate(due, inSameDayAs: now) { return "Due today" }
            if calendar.isDate(due, inSameDayAs: tomorrow) { return "Due tomorrow" }
            return "Due \(due.formatted(.dateTime.month(.abbreviated).day()))"
        }
        let seconds = due.timeIntervalSince(now)
        if seconds < 60 { return "Due now" }
        if seconds < 3600 { return "In \(Int(ceil(seconds / 60))) min" }
        if calendar.isDate(due, inSameDayAs: now) {
            return "Today · \(due.formatted(date: .omitted, time: .shortened))"
        }
        if calendar.isDate(due, inSameDayAs: tomorrow) {
            return "Tomorrow · \(due.formatted(date: .omitted, time: .shortened))"
        }
        return due.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    /// Show the nearest upcoming due item. If only overdue items remain, show
    /// the most recently overdue one. Undated/completed items are filtered upstream.
    static func next(in reminders: [ReminderInfo], now: Date = Date(), calendar: Calendar = .current) -> ReminderInfo? {
        let upcoming = reminders.filter { !$0.isOverdue(at: now, calendar: calendar) }
            .sorted { $0.due == $1.due ? $0.id < $1.id : $0.due < $1.due }
        return upcoming.first ?? reminders.sorted {
            $0.due == $1.due ? $0.id < $1.id : $0.due > $1.due
        }.first
    }

    static func from(_ reminder: EKReminder) -> ReminderInfo? {
        guard !reminder.isCompleted, let components = reminder.dueDateComponents,
              let (due, dateOnly) = dueDate(from: components) else { return nil }
        let color = (reminder.calendar?.cgColor).flatMap { NSColor(cgColor: $0)?.usingColorSpace(.sRGB) }
        return ReminderInfo(id: reminder.calendarItemIdentifier,
                            title: reminder.title?.isEmpty == false ? reminder.title! : "Untitled reminder",
                            listName: reminder.calendar?.title ?? "Reminders", due: due, dateOnly: dateOnly,
                            colorComponents: color.map { [$0.redComponent, $0.greenComponent, $0.blueComponent] }
                                ?? [0.66, 0.60, 1.0])
    }
}

enum ReminderAccess: Equatable { case notDetermined, allowed, denied }
enum ReminderCardState: Equatable {
    case connect, denied, loading, empty, failed
    case ready(ReminderInfo)
}

@MainActor
protocol ReminderStoreReading: AnyObject {
    var access: ReminderAccess { get }
    func requestAccess(_ completion: @escaping @MainActor (Bool) -> Void)
    func fetch(_ completion: @escaping @MainActor ([ReminderInfo]?) -> Void) -> Any
    func cancel(_ request: Any)
}

@MainActor
final class AppleReminderStore: ReminderStoreReading {
    private lazy var store = EKEventStore()

    var access: ReminderAccess {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .notDetermined: return .notDetermined
        case .fullAccess: return .allowed
        default: return .denied
        }
    }

    func requestAccess(_ completion: @escaping @MainActor (Bool) -> Void) {
        store.requestFullAccessToReminders { [weak self] granted, _ in
            Task { @MainActor in
                // The pre-permission store can retain an empty / unauthorized
                // snapshot. Recreate it before the first authorized fetch.
                if granted { self?.store = EKEventStore() }
                completion(granted)
            }
        }
    }

    func fetch(_ completion: @escaping @MainActor ([ReminderInfo]?) -> Void) -> Any {
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        return store.fetchReminders(matching: predicate) { reminders in
            // Only keep display metadata, never notes, attachments, or a disk cache.
            let items = reminders.map { $0.compactMap(ReminderInfo.from) }
            Task { @MainActor in completion(items) }
        }
    }

    func cancel(_ request: Any) { store.cancelFetchRequest(request) }
}

@MainActor
final class ReminderService: ObservableObject {
    @Published private(set) var state: ReminderCardState
    @Published private(set) var requestingAccess = false
    private let store: ReminderStoreReading
    private var active = false
    private var generation = 0
    private var request: Any?
    private var fetching = false
    private var refreshAgain = false
    private var timeout: Task<Void, Never>?
    private var changes: AnyCancellable?
    private var awaitingAuthorizationUpdate = false

    private var currentAccess: ReminderAccess {
        let reported = store.access
        // EventKit's synchronous status can briefly lag its successful permission
        // callback. Honor that explicit grant instead of reverting to Connect.
        // A definitive denial/restriction always wins, including later revocation.
        if reported != .notDetermined { awaitingAuthorizationUpdate = false }
        return reported == .notDetermined && awaitingAuthorizationUpdate ? .allowed : reported
    }

    init(store: ReminderStoreReading? = nil, preview: ReminderCardState? = nil) {
        let store = store ?? AppleReminderStore()
        self.store = store
        state = preview ?? (store.access == .allowed ? .loading : store.access == .denied ? .denied : .connect)
    }

    func start(now: Date = Date()) {
        guard !active else { return }
        active = true
        changes = NotificationCenter.default.publisher(for: .EKEventStoreChanged)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
        refresh(now: now)
    }

    func stop() {
        active = false
        changes = nil
        cancelPending()
    }

    private func cancelPending() {
        generation += 1
        if let request { store.cancel(request) }
        request = nil
        fetching = false
        refreshAgain = false
        timeout?.cancel()
        timeout = nil
    }

    /// Never asks for access automatically, including at startup.
    func refresh(now: Date = Date()) {
        guard active else { return }
        let access = currentAccess
        guard access == .allowed else {
            cancelPending()
            state = access == .notDetermined ? .connect : .denied
            return
        }
        if fetching { refreshAgain = true; return }
        generation += 1
        let token = generation
        fetching = true
        if case .ready = state {} else { state = .loading }
        request = store.fetch { [weak self] items in
            guard let self, self.active, self.generation == token else { return }
            self.request = nil
            self.fetching = false
            self.timeout?.cancel()
            self.timeout = nil
            guard self.currentAccess == .allowed else { self.refresh(); return }
            if let items {
                self.state = ReminderInfo.next(in: items, now: now).map(ReminderCardState.ready) ?? .empty
            } else {
                self.state = .failed
            }
            if self.refreshAgain {
                self.refreshAgain = false
                self.refresh()
            }
        }
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            guard let self, self.active, self.generation == token, self.fetching else { return }
            self.cancelPending()
            self.state = .failed
        }
    }

    func requestAccess() {
        guard !requestingAccess else { return }
        guard currentAccess == .notDetermined else { refresh(); return }
        requestingAccess = true
        store.requestAccess { [weak self] granted in
            guard let self else { return }
            self.requestingAccess = false
            self.awaitingAuthorizationUpdate = granted
            self.state = granted ? .loading : .denied
            if granted { self.refresh() } // No fetch if closed during the prompt.
        }
    }

    func openReminders() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders") {
            NSWorkspace.shared.open(url)
        }
    }

    func openSettings() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") {
            NSWorkspace.shared.open(url)
        }
    }
}
