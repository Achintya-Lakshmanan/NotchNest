import XCTest
@testable import NotchNest

final class DeadlineTests: XCTestCase {
    private let cal = Calendar.current
    private var midnight: Date { cal.startOfDay(for: Date()) }

    private func event(_ title: String, start: Date, hours: Double, allDay: Bool = false) -> CalEvent {
        CalEvent(id: title, title: title, start: start, end: start.addingTimeInterval(hours * 3600),
                 isAllDay: allDay, colorComponents: [1, 0, 0, 1])
    }

    func testRegistrarMidnightEventsBecomeEndOfDayDeadlines() {
        let tomorrow = cal.date(byAdding: .day, value: 1, to: midnight)!
        let deadlines = Deadline.from([event("Late Add - Deadline until 11:59 p.m. (ET)*", start: tomorrow, hours: 1)])
        XCTAssertEqual(deadlines.count, 1)
        XCTAssertEqual(deadlines[0].title, "Late Add")
        XCTAssertEqual(deadlines[0].due, cal.date(byAdding: .day, value: 2, to: midnight)!.addingTimeInterval(-1))
    }

    func testKeywordTimedEventsAreDueAtTheirStart() {
        let start = Date().addingTimeInterval(5 * 3600)
        let deadlines = Deadline.from([event("HW3 due", start: start, hours: 0.5)])
        XCTAssertEqual(deadlines.first?.due, start)
    }

    func testOrdinaryEventsHolidaysAndPastDeadlinesAreSkipped() {
        let tomorrow = cal.date(byAdding: .day, value: 1, to: midnight)!
        let deadlines = Deadline.from([
            event("CSE 597 - LEC", start: Date().addingTimeInterval(3600), hours: 1),
            event("Thanksgiving", start: tomorrow, hours: 24, allDay: true),
            event("Quiz 2", start: Date().addingTimeInterval(-7200), hours: 1),
        ])
        XCTAssertTrue(deadlines.isEmpty)
    }

    func testAllDayDeadlinesUseTheEndOfTheirLastDay() {
        let tomorrow = cal.date(byAdding: .day, value: 1, to: midnight)!
        let d = Deadline.from([event("Declare Major - Deadline (Graduating Students)", start: tomorrow, hours: 24, allDay: true)])
        XCTAssertEqual(d.first?.title, "Declare Major")
        XCTAssertEqual(d.first?.due, tomorrow.addingTimeInterval(24 * 3600 - 1))
    }

    func testLastDayItemsCountAndStudySessionsDoNot() {
        let tomorrow = cal.date(byAdding: .day, value: 1, to: midnight)!
        let titles = Deadline.from([
            event("Last Day to Withdraw", start: tomorrow, hours: 24, allDay: true),
            event("Exam review session", start: tomorrow.addingTimeInterval(15 * 3600), hours: 1),
            event("Lab 3 report due", start: tomorrow.addingTimeInterval(17 * 3600), hours: 0.5),
        ]).map(\.title)
        XCTAssertEqual(titles, ["Lab 3 report due", "Last Day to Withdraw"])
    }

    func testRealAssignmentsMentioningReviewOrStudyStillCount() {
        for title in ["Peer Review due", "Case Study 3 due", "Literature Review submission",
                      "Final exam", "Midterm review worksheet due"] {
            XCTAssertTrue(Deadline.looksLikeDeadline(title), title)
        }
        for title in ["Midterm review", "Exam prep", "Study group: quiz", "Office hours (HW help)",
                      "Due process lecture", "Final review session"] {
            XCTAssertFalse(Deadline.looksLikeDeadline(title), title)
        }
    }

    func testCountdownAndUrgency() {
        let now = Date()
        let soon = Deadline(id: "a", title: "a", fullTitle: "a", due: now.addingTimeInterval(5 * 3600), colorComponents: [])
        let later = Deadline(id: "b", title: "b", fullTitle: "b", due: now.addingTimeInterval(3 * 86400), colorComponents: [])
        XCTAssertEqual(soon.countdown(at: now), "in 5h")
        XCTAssertTrue(soon.isUrgent(at: now))
        XCTAssertEqual(later.countdown(at: now), "in 3d")
        XCTAssertFalse(later.isUrgent(at: now))
    }
}

final class LyricsTests: XCTestCase {
    func testParsesLRCIncludingRepeatedTimestamps() {
        let lines = Lyrics.parseLRC("[ar:Someone]\n[00:12.50]Hello\n[00:05.00][00:30.00]Chorus\nno stamp")
        XCTAssertEqual(lines.map(\.text), ["Chorus", "Hello", "Chorus"])
        XCTAssertEqual(lines.map(\.time), [5, 12.5, 30])
    }

    func testCurrentIndexFollowsPlayback() {
        let lines = [LyricLine(time: 5, text: "a"), LyricLine(time: 10, text: "b")]
        XCTAssertNil(Lyrics.currentIndex(in: lines, at: 2))
        XCTAssertEqual(Lyrics.currentIndex(in: lines, at: 7), 0)
        XCTAssertEqual(Lyrics.currentIndex(in: lines, at: 99), 1)
    }

    func testDecodePrefersSyncedThenPlain() {
        XCTAssertEqual(LyricsService.decode(Data(#"{"instrumental":true}"#.utf8)), .instrumental)
        XCTAssertEqual(LyricsService.decode(Data(#"{"plainLyrics":"la la","syncedLyrics":null}"#.utf8)), .plain("la la"))
        XCTAssertEqual(LyricsService.decode(Data(#"{"syncedLyrics":"[00:01.00]hi"}"#.utf8)),
                       .synced([LyricLine(time: 1, text: "hi")]))
        XCTAssertEqual(LyricsService.decode(Data("not json".utf8)), .unavailable)
    }
}

final class ClassModeTests: XCTestCase {
    func testPillLabelsBeforeAndDuringClass() {
        let now = Date()
        let upcoming = CalEvent(id: "u", title: "CSE", start: now.addingTimeInterval(12 * 60),
                                end: now.addingTimeInterval(62 * 60), isAllDay: false, colorComponents: [])
        let live = CalEvent(id: "l", title: "CSE", start: now.addingTimeInterval(-38 * 60),
                            end: now.addingTimeInterval(12 * 60), isAllDay: false, colorComponents: [])
        XCTAssertEqual(MeetingPill.label(upcoming, at: now), "in 12m")
        XCTAssertEqual(MeetingPill.label(live, at: now), "12m left")
        XCTAssertEqual(MeetingPill.progress(live, at: now), 0.76, accuracy: 0.01)
        let long = CalEvent(id: "x", title: "Lab", start: now.addingTimeInterval(-60),
                            end: now.addingTimeInterval(119 * 60), isAllDay: false, colorComponents: [])
        XCTAssertEqual(MeetingPill.label(long, at: now), "1h59m")
    }

    func testLocationDropsMeetingLinks() {
        XCTAssertEqual(CalendarService.place(from: "Willard 062"), "Willard 062")
        XCTAssertNil(CalendarService.place(from: "https://psu.zoom.us/j/123"))
        XCTAssertEqual(CalendarService.place(from: "Room 5, https://meet.google.com/abc"), "Room 5")
    }
}

@MainActor
final class ClaudeAlertTests: XCTestCase {
    private func state() -> NotchState {
        let metrics = NotchMetrics(notchWidth: 200, notchHeight: 32, screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982))
        let s = NotchState(metrics: metrics)
        s.disableLiveRefresh = true
        return s
    }

    func testLowFiveHourWindowAlertsOncePerWindow() {
        let s = state()
        let now = Date()
        let usage = WeeklyUsage(usedPercent: 20, resetsAt: now.addingTimeInterval(86400), fetchedAt: now,
                                session: .init(usedPercent: 94, resetsAt: now.addingTimeInterval(3600)))
        s.checkClaudeAlerts(usage, now: now)
        XCTAssertEqual(s.alert?.title, "Claude 5-hour limit: 6% left")
        s.alert = nil
        s.checkClaudeAlerts(usage, now: now)
        XCTAssertNil(s.alert)
    }

    func testHealthyUsageDoesNotAlert() {
        let s = state()
        let now = Date()
        s.checkClaudeAlerts(WeeklyUsage(usedPercent: 20, resetsAt: now.addingTimeInterval(86400), fetchedAt: now,
                                        session: .init(usedPercent: 40, resetsAt: now.addingTimeInterval(3600))), now: now)
        XCTAssertNil(s.alert)
    }
}

@MainActor
final class AlertQueueTests: XCTestCase {
    private func state() -> NotchState {
        let s = NotchState(metrics: NotchMetrics(notchWidth: 200, notchHeight: 32,
                                                 screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982)))
        s.disableLiveRefresh = true
        return s
    }

    private func toast(_ title: String) -> AlertToast {
        AlertToast(symbol: "bell", title: title, subtitle: "", tint: .orange)
    }

    func testAlertWaitsWhileExpandedAndShowsAfterCollapse() async throws {
        let s = state()
        s.isExpanded = true
        s.showAlert(toast("Class soon"))
        XCTAssertNil(s.alert)
        XCTAssertEqual(s.pendingAlertCount, 1)
        s.isExpanded = false
        for _ in 0..<100 where s.alert == nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(s.alert?.title, "Class soon")
    }

    func testSecondAlertQueuesBehindTheFirst() {
        let s = state()
        s.showAlert(toast("One"))
        s.showAlert(toast("Two"))
        XCTAssertEqual(s.alert?.title, "One")
        XCTAssertEqual(s.pendingAlertCount, 1)
    }

    func testSameKeyReplacesInsteadOfQueueing() {
        let s = state()
        s.showAlert(toast("Caps Lock On"), key: "capslock")
        s.showAlert(toast("Caps Lock Off"), key: "capslock")
        XCTAssertEqual(s.alert?.title, "Caps Lock Off")
        XCTAssertEqual(s.pendingAlertCount, 0)
    }

    /// Hovering a popup opens the card; the popup must come back afterwards.
    func testPopupSurvivesOpeningTheCard() async throws {
        let s = state()
        s.showAlert(toast("Lecture soon"), duration: 0.3)
        XCTAssertEqual(s.alert?.title, "Lecture soon")
        s.isExpanded = true
        for _ in 0..<100 where s.alert != nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNil(s.alert)
        XCTAssertEqual(s.pendingAlertCount, 1)
        // Longer than its duration: its countdown must not run while hidden.
        try await Task.sleep(for: .milliseconds(400))
        s.isExpanded = false
        for _ in 0..<100 where s.alert == nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(s.alert?.title, "Lecture soon")
    }

    func testHeadsUpIsDroppedIfClassStartsBeforeItCanShow() async throws {
        let s = state()
        s.isExpanded = true
        let now = Date()
        s.todayEvents = [CalEvent(id: "x@1", title: "CSE 597", start: now.addingTimeInterval(0.2),
                                  end: now.addingTimeInterval(3600), isAllDay: false, colorComponents: [])]
        s.checkClassHeadsUp(now: now)
        XCTAssertEqual(s.pendingAlertCount, 1)
        try await Task.sleep(for: .milliseconds(400))
        s.isExpanded = false
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(s.alert, "Never say 'Starts in…' after class started")
    }
}

@MainActor
final class CalendarRefreshTests: XCTestCase {
    /// Browsing next month must not freeze today's events (class mode).
    func testTodayUpdatesWhileBrowsingAnotherMonth() {
        let s = NotchState(metrics: NotchMetrics(notchWidth: 200, notchHeight: 32,
                                                 screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982)))
        s.disableLiveRefresh = true
        let thisMonth = NotchState.startOfMonth(Date())
        s.visibleMonth = Calendar.current.date(byAdding: .month, value: 1, to: thisMonth)!
        let lecture = CalEvent(id: "l@1", title: "Lecture", start: Date().addingTimeInterval(300),
                               end: Date().addingTimeInterval(3600), isAllDay: false, colorComponents: [])
        s.applyCalendarResults(month: [lecture], for: thisMonth, today: [lecture], deadlines: [])
        XCTAssertEqual(s.todayEvents, [lecture])
        XCTAssertTrue(s.monthEvents.isEmpty, "A stale month response still doesn't touch the grid")
    }
}

final class OccurrenceIDTests: XCTestCase {
    func testOccurrencesOfOneSeriesDifferButAreStable() {
        let monday = Date(timeIntervalSince1970: 1_800_000_000)
        let wednesday = monday.addingTimeInterval(2 * 86400)
        XCTAssertNotEqual(CalendarService.occurrenceID(base: "E1", start: monday),
                          CalendarService.occurrenceID(base: "E1", start: wednesday))
        XCTAssertEqual(CalendarService.occurrenceID(base: "E1", start: monday),
                       CalendarService.occurrenceID(base: "E1", start: monday))
    }
}

final class ClaudePollingTests: XCTestCase {
    func testChecksMoreOftenNearALimit() {
        let now = Date()
        let healthy = WeeklyUsage(usedPercent: 20, resetsAt: now.addingTimeInterval(86400), fetchedAt: now,
                                  planType: nil, session: .init(usedPercent: 40, resetsAt: now.addingTimeInterval(3600)))
        let low = WeeklyUsage(usedPercent: 20, resetsAt: now.addingTimeInterval(86400), fetchedAt: now,
                              planType: nil, session: .init(usedPercent: 75, resetsAt: now.addingTimeInterval(3600)))
        XCTAssertEqual(ClaudeUsageService.backgroundInterval(for: healthy, pluggedIn: true, now: now), 600)
        XCTAssertEqual(ClaudeUsageService.backgroundInterval(for: healthy, pluggedIn: false, now: now), 1800)
        XCTAssertEqual(ClaudeUsageService.backgroundInterval(for: low, pluggedIn: true, now: now), 300)
        XCTAssertEqual(ClaudeUsageService.backgroundInterval(for: low, pluggedIn: false, now: now), 900)
        let veryLow = WeeklyUsage(usedPercent: 20, resetsAt: now.addingTimeInterval(86400), fetchedAt: now,
                                  planType: nil, session: .init(usedPercent: 88, resetsAt: now.addingTimeInterval(3600)))
        XCTAssertEqual(ClaudeUsageService.backgroundInterval(for: veryLow, pluggedIn: false, now: now), 300)
        XCTAssertEqual(ClaudeUsageService.backgroundInterval(for: nil, pluggedIn: true, now: now), 600)
        // A low weekly allowance can last for days: no faster polling.
        let weeklyLow = WeeklyUsage(usedPercent: 85, resetsAt: now.addingTimeInterval(4 * 86400), fetchedAt: now,
                                    planType: nil, session: .init(usedPercent: 10, resetsAt: now.addingTimeInterval(3600)))
        XCTAssertEqual(ClaudeUsageService.backgroundInterval(for: weeklyLow, pluggedIn: false, now: now), 1800)
    }
}

@MainActor
final class ClassHeadsUpTests: XCTestCase {
    func testEachOccurrenceOfARecurringClassGetsItsOwnHeadsUp() {
        let s = NotchState(metrics: NotchMetrics(notchWidth: 200, notchHeight: 32,
                                                 screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982)))
        s.disableLiveRefresh = true
        let now = Date()
        // Same EventKit identifier, different start → different occurrence IDs.
        let monday = CalEvent(id: "lec@1", title: "CSE 597", start: now.addingTimeInterval(8 * 60),
                              end: now.addingTimeInterval(58 * 60), isAllDay: false, colorComponents: [])
        s.todayEvents = [monday]
        s.checkClassHeadsUp(now: now)
        XCTAssertEqual(s.alert?.title, "CSE 597")
        s.alert = nil
        s.checkClassHeadsUp(now: now)
        XCTAssertNil(s.alert, "One heads-up per occurrence")
        let wednesday = CalEvent(id: "lec@2", title: "CSE 597", start: now.addingTimeInterval(9 * 60),
                                 end: now.addingTimeInterval(59 * 60), isAllDay: false, colorComponents: [])
        s.todayEvents = [wednesday]
        s.checkClassHeadsUp(now: now)
        XCTAssertNotNil(s.alert)
    }

    func testLiveLongBlockDoesNotHideTheNextClass() {
        let s = NotchState(metrics: NotchMetrics(notchWidth: 200, notchHeight: 32,
                                                 screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982)))
        let now = Date()
        let block = CalEvent(id: "b", title: "Study block", start: now.addingTimeInterval(-3600),
                             end: now.addingTimeInterval(3 * 3600), isAllDay: false, colorComponents: [])
        let lecture = CalEvent(id: "l", title: "Lecture", start: now.addingTimeInterval(5 * 60),
                               end: now.addingTimeInterval(55 * 60), isAllDay: false, colorComponents: [])
        s.todayEvents = [block, lecture]
        XCTAssertEqual(s.imminentEvent(now: now)?.id, "l")
        XCTAssertEqual(s.upcomingEvent(now: now)?.id, "l")
    }

    func testFreeEventsAreNotClasses() {
        let s = NotchState(metrics: NotchMetrics(notchWidth: 200, notchHeight: 32,
                                                 screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982)))
        let now = Date()
        s.todayEvents = [CalEvent(id: "f", title: "Hold", start: now.addingTimeInterval(300),
                                  end: now.addingTimeInterval(3600), isAllDay: false, colorComponents: [], isFree: true)]
        XCTAssertNil(s.imminentEvent(now: now))
    }
}

final class LyricsSearchTests: XCTestCase {
    func testSearchPicksClosestLengthWithSyncedLyrics() {
        let json = #"[{"duration":180,"plainLyrics":"wrong cut"},{"duration":244,"syncedLyrics":"[00:01.00]right"},{"duration":243,"plainLyrics":"plain only"}]"#
        XCTAssertEqual(LyricsService.bestMatch(Data(json.utf8), duration: 244.4), .synced([LyricLine(time: 1, text: "right")]))
        XCTAssertEqual(LyricsService.bestMatch(Data(#"[{"duration":100,"plainLyrics":"x"}]"#.utf8), duration: 244), .unavailable)
    }

    func testEmptyResultDoesNotHideOneWithLyrics() {
        let json = #"[{"duration":244,"syncedLyrics":null,"plainLyrics":""},{"duration":242,"plainLyrics":"words"}]"#
        XCTAssertEqual(LyricsService.bestMatch(Data(json.utf8), duration: 244), .plain("words"))
    }

    func testSearchTitleDropsDecorations() {
        XCTAssertEqual(LyricsService.searchTitle("Sicko Mode (feat. Drake)"), "Sicko Mode")
        XCTAssertEqual(LyricsService.searchTitle("Heroes - 2017 Remaster"), "Heroes")
        XCTAssertEqual(LyricsService.searchTitle("Yellow (Live at Glastonbury)"), "Yellow")
        XCTAssertEqual(LyricsService.searchTitle("Hey Jude [Remastered 2015]"), "Hey Jude")
        XCTAssertEqual(LyricsService.searchTitle("Anti-Hero"), "Anti-Hero")
        XCTAssertEqual(LyricsService.searchTitle("Love - Lana"), "Love - Lana")
    }
}

final class MultiDayEventTests: XCTestCase {
    func testMultiDayEventAppearsOnEveryDayItTouches() {
        let cal = Calendar.current
        let day1 = cal.startOfDay(for: Date())
        let trip = CalEvent(id: "t", title: "Conference", start: day1.addingTimeInterval(9 * 3600),
                            end: day1.addingTimeInterval(2 * 86400 + 12 * 3600), isAllDay: false, colorComponents: [])
        XCTAssertTrue(trip.occurs(on: day1))
        XCTAssertTrue(trip.occurs(on: day1.addingTimeInterval(86400)))
        XCTAssertTrue(trip.occurs(on: day1.addingTimeInterval(2 * 86400)))
        XCTAssertFalse(trip.occurs(on: day1.addingTimeInterval(3 * 86400)))
    }
}

@MainActor
final class TimerTests: XCTestCase {
    func testStepperClampsAndPomodoroStartsWithFocus() {
        let s = NotchState(metrics: NotchMetrics(notchWidth: 200, notchHeight: 32,
                                                 screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982)))
        s.timerDuration = 60
        s.timerRemaining = 60
        s.adjustTimer(byMinutes: -5)
        XCTAssertEqual(s.timerDuration, 60)
        s.adjustTimer(byMinutes: 9)
        XCTAssertEqual(s.timerDuration, 600)
        s.startPomodoro()
        XCTAssertEqual(s.pomodoro, PomodoroState(phase: .focus, round: 1))
        XCTAssertEqual(s.timerDuration, 25 * 60)
        XCTAssertEqual(PomodoroState.Phase.rest.duration(round: 4), 15 * 60)
        s.resetTimer()
        XCTAssertNil(s.pomodoro)
    }
}
