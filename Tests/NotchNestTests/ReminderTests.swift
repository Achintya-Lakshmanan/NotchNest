import XCTest
import EventKit
@testable import NotchNest

final class ReminderTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 12))! }
    private func item(_ id: String, offset: TimeInterval, dateOnly: Bool = false) -> ReminderInfo {
        ReminderInfo(id: id, title: "Example reminder", listName: "Personal",
                     due: now.addingTimeInterval(offset), dateOnly: dateOnly, colorComponents: [0.7, 0.6, 1])
    }

    func testNearestUpcomingTakesPriorityOverOldOverdueItems() {
        let reminders = [item("old", offset: -86400), item("later", offset: 7200), item("next", offset: 2400)]
        XCTAssertEqual(ReminderInfo.next(in: reminders, now: now, calendar: calendar)?.id, "next")
    }

    func testOnlyOverdueUsesMostRecent() {
        XCTAssertEqual(ReminderInfo.next(in: [item("old", offset: -86400), item("recent", offset: -600)],
                                         now: now, calendar: calendar)?.id, "recent")
    }

    func testEqualDatesHaveStableSelection() {
        XCTAssertEqual(ReminderInfo.next(in: [item("b", offset: 600), item("a", offset: 600)], now: now)?.id, "a")
    }

    func testDateOnlyTodayIsNotOverdueUntilNextDay() {
        let reminder = item("today", offset: -12 * 3600, dateOnly: true)
        XCTAssertFalse(reminder.isOverdue(at: now, calendar: calendar))
        XCTAssertEqual(reminder.dueLabel(at: now, calendar: calendar), "Due today")
        XCTAssertTrue(reminder.isOverdue(at: now.addingTimeInterval(24 * 3600), calendar: calendar))
    }

    func testDateOnlyLabelsAndMinuteCountdown() {
        XCTAssertEqual(item("next", offset: 2400).dueLabel(at: now, calendar: calendar), "In 40 min")
        XCTAssertEqual(item("now", offset: 10).dueLabel(at: now, calendar: calendar), "Due now")
        XCTAssertEqual(item("late", offset: -10).dueLabel(at: now, calendar: calendar), "Overdue")
        XCTAssertEqual(item("tomorrow", offset: 86400, dateOnly: true).dueLabel(at: now, calendar: calendar), "Due tomorrow")
    }

    func testEmptySelectionAndMissingDateComponents() {
        XCTAssertNil(ReminderInfo.next(in: [], now: now))
        XCTAssertNil(ReminderInfo.dueDate(from: DateComponents(hour: 10), calendar: calendar))
    }

    func testDueComponentsRespectTimeZoneAndDateOnly() throws {
        let dateOnly = try XCTUnwrap(ReminderInfo.dueDate(
            from: DateComponents(year: 2026, month: 9, day: 18), calendar: calendar))
        XCTAssertTrue(dateOnly.1)
        XCTAssertEqual(dateOnly.0, calendar.startOfDay(for: now))
        let timed = try XCTUnwrap(ReminderInfo.dueDate(from: DateComponents(
            timeZone: TimeZone(secondsFromGMT: 0), year: 2026, month: 9, day: 18, hour: 16), calendar: calendar))
        XCTAssertFalse(timed.1)
        XCTAssertEqual(timed.0, now)
    }

    func testAllDayAcrossDaylightSavingTransition() throws {
        let due = try XCTUnwrap(ReminderInfo.dueDate(from: DateComponents(year: 2026, month: 3, day: 8), calendar: calendar)).0
        let reminder = ReminderInfo(id: "dst", title: "Due today", listName: "Personal", due: due,
                                    dateOnly: true, colorComponents: [])
        let endOfDay = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 23, minute: 59))!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: due)!
        XCTAssertFalse(reminder.isOverdue(at: endOfDay, calendar: calendar))
        XCTAssertTrue(reminder.isOverdue(at: tomorrow, calendar: calendar))
    }

    func testUndatedAndCompletedRemindersAreExcluded() {
        let store = EKEventStore()
        let reminder = EKReminder(eventStore: store)
        reminder.title = "Unsaved test only"
        XCTAssertNil(ReminderInfo.from(reminder))
        reminder.dueDateComponents = DateComponents(year: 2026, month: 9, day: 18)
        reminder.isCompleted = true
        XCTAssertNil(ReminderInfo.from(reminder))
    }

    @MainActor
    func testNoPromptOrFetchUntilUserConnects() async {
        let store = FakeReminderStore()
        let service = ReminderService(store: store)
        service.start()
        XCTAssertEqual(service.state, .connect)
        XCTAssertEqual(store.requests, 0)
        XCTAssertEqual(store.fetches.count, 0)
        service.requestAccess()
        XCTAssertEqual(store.requests, 1)
        store.access = .allowed
        store.permission?(true)
        XCTAssertEqual(store.fetches.count, 1)
        service.stop()
    }

    @MainActor
    func testDeniedPermissionDoesNotQueryReminders() async {
        let store = FakeReminderStore()
        store.access = .denied
        let service = ReminderService(store: store)
        service.start()
        XCTAssertEqual(service.state, .denied)
        XCTAssertTrue(store.fetches.isEmpty)
        service.requestAccess()
        XCTAssertEqual(store.requests, 0)
        service.stop()
    }

    @MainActor
    func testSuccessfulGrantLoadsEvenWhileStatusStillSaysNotDetermined() async {
        let store = FakeReminderStore()
        let service = ReminderService(store: store)
        service.start()
        service.requestAccess()
        store.permission?(true) // The OS status cache has not caught up yet.
        XCTAssertEqual(service.state, .loading)
        XCTAssertEqual(store.fetches.count, 1)
        let reminder = item("next", offset: 3600)
        store.fetches[0]([reminder])
        XCTAssertEqual(service.state, .ready(reminder))
        service.requestAccess()
        XCTAssertEqual(store.requests, 1, "Never repeat a granted permission request")
        store.access = .denied
        service.refresh()
        XCTAssertEqual(service.state, .denied, "Revocation overrides the earlier grant")
        service.stop()
    }

    @MainActor
    func testGrantWhileClosedSurvivesDelayedAuthorizationStatus() async {
        let store = FakeReminderStore()
        let service = ReminderService(store: store)
        service.start()
        service.requestAccess()
        service.stop()
        store.permission?(true)
        XCTAssertTrue(store.fetches.isEmpty)
        service.start()
        XCTAssertEqual(store.fetches.count, 1)
        store.access = .allowed
        store.fetches[0]([item("next", offset: 3600)])
        store.access = .notDetermined // A later privacy reset must not reuse the grant.
        service.refresh()
        XCTAssertEqual(service.state, .connect)
        service.stop()
    }

    @MainActor
    func testConnectRefreshesWhenPermissionWasAlreadyGrantedElsewhere() async {
        let store = FakeReminderStore()
        let service = ReminderService(store: store)
        service.start()
        store.access = .allowed
        service.requestAccess()
        XCTAssertEqual(store.requests, 0)
        XCTAssertEqual(store.fetches.count, 1)
        service.stop()
    }

    @MainActor
    func testDeniedCallbackNeverFetchesWhenStatusLags() async {
        let store = FakeReminderStore()
        let service = ReminderService(store: store)
        service.start()
        service.requestAccess()
        store.permission?(false)
        XCTAssertEqual(service.state, .denied)
        XCTAssertTrue(store.fetches.isEmpty)
        XCTAssertFalse(service.requestingAccess)
        service.stop()
    }

    @MainActor
    func testCompletionAdvancesCardAndFailureIsNotEmpty() async {
        let store = FakeReminderStore()
        store.access = .allowed
        let service = ReminderService(store: store)
        let first = item("first", offset: 600)
        let second = item("second", offset: 3600)
        service.start(now: now)
        store.fetches[0]([first, second])
        XCTAssertEqual(service.state, .ready(first))
        service.refresh(now: now)
        store.fetches[1]([second])
        XCTAssertEqual(service.state, .ready(second))
        service.refresh(now: now)
        store.fetches[2](nil)
        XCTAssertEqual(service.state, .failed)
        service.refresh(now: now)
        store.fetches[3]([])
        XCTAssertEqual(service.state, .empty)
        service.stop()
    }

    @MainActor
    func testClosingStopsFetchAndIgnoresLateResponse() async {
        let store = FakeReminderStore()
        store.access = .allowed
        let service = ReminderService(store: store)
        service.start()
        service.stop()
        XCTAssertEqual(store.cancelled.count, 1)
        store.fetches[0]([item("late", offset: 600)])
        XCTAssertEqual(service.state, .loading)
        service.refresh()
        XCTAssertEqual(store.fetches.count, 1)
    }

    @MainActor
    func testAccessRevocationClearsExistingCard() async {
        let store = FakeReminderStore()
        store.access = .allowed
        let service = ReminderService(store: store)
        service.start()
        store.fetches[0]([item("first", offset: 600)])
        store.access = .denied
        service.refresh()
        XCTAssertEqual(service.state, .denied)
        service.stop()
    }

    @MainActor
    func testGrantAfterClosingDoesNotFetchInBackground() async {
        let store = FakeReminderStore()
        let service = ReminderService(store: store)
        service.start()
        service.requestAccess()
        service.stop()
        store.access = .allowed
        store.permission?(true)
        XCTAssertTrue(store.fetches.isEmpty)
        XCTAssertFalse(service.requestingAccess)
        service.start()
        XCTAssertEqual(store.fetches.count, 1)
        service.stop()
    }

    @MainActor
    func testChangesDuringFetchAreCoalescedIntoOneFollowup() async {
        let store = FakeReminderStore()
        store.access = .allowed
        let service = ReminderService(store: store)
        service.start(now: now)
        service.refresh(now: now)
        service.refresh(now: now)
        XCTAssertEqual(store.fetches.count, 1)
        store.fetches[0]([])
        XCTAssertEqual(store.fetches.count, 2)
        store.fetches[1]([])
        XCTAssertEqual(service.state, .empty)
        service.stop()
    }
}

@MainActor
private final class FakeReminderStore: ReminderStoreReading {
    var access: ReminderAccess = .notDetermined
    var requests = 0
    var permission: (@MainActor (Bool) -> Void)?
    var fetches: [@MainActor ([ReminderInfo]?) -> Void] = []
    var cancelled: [Int] = []
    func requestAccess(_ completion: @escaping @MainActor (Bool) -> Void) { requests += 1; permission = completion }
    func fetch(_ completion: @escaping @MainActor ([ReminderInfo]?) -> Void) -> Any {
        fetches.append(completion)
        return fetches.count - 1
    }
    func cancel(_ request: Any) { cancelled.append(request as! Int) }
}
