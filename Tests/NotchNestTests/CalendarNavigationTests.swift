import XCTest
@testable import NotchNest

final class CalendarNavigationTests: XCTestCase {
    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @MainActor
    private func makeState() -> NotchState {
        let state = NotchState(metrics: NotchMetrics(notchWidth: 200, notchHeight: 37, screenFrame: .zero))
        state.disableLiveRefresh = true
        return state
    }

    @MainActor
    func testReturningToCalendarSelectsCurrentDay() async {
        let state = makeState()
        state.goToToday(now: date(2026, 9, 17))
        state.select(date(2026, 9, 10))
        state.goToToday(now: date(2026, 9, 18))
        XCTAssertEqual(state.selectedDate, date(2026, 9, 18, hour: 0))
        XCTAssertEqual(state.visibleMonth, date(2026, 9, 1, hour: 0))
    }

    @MainActor
    func testReopeningReturnsFromBrowsedMonthToToday() async {
        let state = makeState()
        state.goToToday(now: date(2026, 9, 18))
        state.changeMonth(by: 3)
        state.select(date(2026, 12, 25))
        state.goToToday(now: date(2026, 9, 18))
        XCTAssertEqual(state.selectedDate, date(2026, 9, 18, hour: 0))
        XCTAssertEqual(state.visibleMonth, date(2026, 9, 1, hour: 0))
    }

    @MainActor
    func testDayRolloverAlsoUpdatesMonthAndYear() async {
        let state = makeState()
        state.goToToday(now: date(2026, 12, 31, hour: 23))
        state.goToToday(now: date(2027, 1, 1, hour: 0))
        XCTAssertEqual(state.selectedDate, date(2027, 1, 1, hour: 0))
        XCTAssertEqual(state.visibleMonth, state.selectedDate)
    }

    @MainActor
    func testBrowsingIsPreservedDuringSameVisit() async {
        let state = makeState()
        state.goToToday(now: date(2026, 9, 18))
        state.changeMonth(by: 1)
        state.select(date(2026, 10, 7))
        state.refreshCalendar()
        XCTAssertEqual(state.visibleMonth, date(2026, 10, 1, hour: 0))
        XCTAssertEqual(state.selectedDate, date(2026, 10, 7, hour: 0))
    }

    @MainActor
    func testReturningToTodayUpdatesRightSideEventSelection() async {
        let state = makeState()
        state.monthEvents = [
            CalEvent(id: "old", title: "Yesterday", start: date(2026, 9, 17),
                     end: date(2026, 9, 17, hour: 13), isAllDay: false, colorComponents: [0, 0, 1, 1]),
            CalEvent(id: "current", title: "Today", start: date(2026, 9, 18),
                     end: date(2026, 9, 18, hour: 13), isAllDay: false, colorComponents: [0, 0, 1, 1])
        ]
        state.select(date(2026, 9, 17))
        XCTAssertEqual(state.selectedDayEvents.map(\.id), ["old"])
        state.goToToday(now: date(2026, 9, 18))
        XCTAssertEqual(state.selectedDayEvents.map(\.id), ["current"])
    }
}
