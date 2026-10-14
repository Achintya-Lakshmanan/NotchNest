import AppKit
import SwiftUI
import XCTest
@testable import NotchNest

final class NotchLayoutTests: XCTestCase {
    @MainActor
    func testTrackingAreaSurvivesWindowResizesAndListensForMovement() throws {
        let host = TrackingHostView(frame: CGRect(x: 0, y: 0, width: 297, height: 32))
        host.updateTrackingAreas()
        let area = try XCTUnwrap(host.trackingAreas.first)
        XCTAssertTrue(area.options.contains(.mouseMoved))
        for index in 0..<30 {
            host.setFrameSize(CGSize(width: 297 + index * 8, height: 32 + index * 8))
            host.updateTrackingAreas()
            XCTAssertEqual(host.trackingAreas.count, 1)
            XCTAssertTrue(host.trackingAreas.first === area)
        }
    }

    @MainActor
    func testHostingContentCannotImposeWindowSizingConstraints() {
        let host = TrackingHostView(frame: CGRect(x: 0, y: 0, width: 540, height: 287))
        let content = NSHostingView(rootView: Text("Oversized intrinsic content").frame(height: 900))
        host.setContent(content)
        XCTAssertTrue(content.sizingOptions.isEmpty)
        XCTAssertTrue(content.translatesAutoresizingMaskIntoConstraints)
        XCTAssertEqual(content.autoresizingMask, [.width, .height])
        XCTAssertEqual(content.frame, host.bounds)
        XCTAssertTrue(host.constraints.isEmpty)
        host.setFrameSize(CGSize(width: 312, height: 37))
        XCTAssertEqual(content.frame, host.bounds)
    }

    @MainActor
    func testCalendarWithLongReminderKeepsTheStandardPanelSize() async throws {
        _ = NSApplication.shared
        let metrics = NotchMetrics(notchWidth: 200, notchHeight: 37,
                                   screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982))
        let reminder = ReminderInfo(id: "layout", title: String(repeating: "A long reminder title ", count: 12),
                                    listName: "Personal", due: Date().addingTimeInterval(3600),
                                    dateOnly: false, colorComponents: [0.7, 0.6, 1])
        let state = NotchState(metrics: metrics, reminders: ReminderService(preview: .ready(reminder)))
        state.disableLiveRefresh = true
        state.calendarAuthorized = true
        state.monthEvents = (0..<20).map { index in
            CalEvent(id: "event-\(index)", title: "Calendar event \(index)", start: Date(),
                     end: Date().addingTimeInterval(3600), isAllDay: false, colorComponents: [0, 0.6, 1, 1])
        }
        let panel = NotchPanel(metrics: metrics)
        panel.isReleasedWhenClosed = false
        defer { panel.close() }
        let hosting = NSHostingView(rootView: NotchRootView(state: state).environmentObject(state))
        panel.trackingHost.setContent(hosting)
        panel.orderFrontRegardless()
        panel.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        state.isExpanded = true
        let expected = metrics.panelFrame(for: metrics.expandedSize)
        panel.setFrame(expected, display: false)
        try await Task.sleep(for: .milliseconds(100))
        state.tab = .calendar
        for _ in 0..<5 {
            panel.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(panel.frame.width, expected.width, accuracy: 1)
        XCTAssertEqual(panel.frame.height, expected.height, accuracy: 1)
        XCTAssertEqual(hosting.frame.width, expected.width, accuracy: 1)
        XCTAssertEqual(hosting.frame.height, expected.height, accuracy: 1)
    }

    @MainActor
    func testConnectReminderPanelStaysCompactDuringTabChanges() async throws {
        _ = NSApplication.shared
        let metrics = NotchMetrics(notchWidth: 200, notchHeight: 32,
                                   screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982))
        let state = NotchState(metrics: metrics, reminders: ReminderService(preview: .connect))
        state.disableLiveRefresh = true
        state.calendarAuthorized = true
        state.monthEvents = [CalEvent(id: "event", title: "Class", start: Date(),
                                      end: Date().addingTimeInterval(3600), isAllDay: false,
                                      colorComponents: [0, 0.6, 1, 1])]
        let panel = NotchPanel(metrics: metrics)
        panel.isReleasedWhenClosed = false
        defer { panel.close() }
        let hosting = NSHostingView(rootView: NotchRootView(state: state).environmentObject(state))
        panel.trackingHost.setContent(hosting)
        panel.orderFrontRegardless()
        for tab in [NotchTab.calendar, .music, .calendar] {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                state.isExpanded = true
                state.tab = tab
            }
            let expected = metrics.panelFrame(for: metrics.expandedSize)
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.05
                panel.animator().setFrame(expected, display: false)
            }
            try await Task.sleep(for: .milliseconds(400))
            panel.contentView?.layoutSubtreeIfNeeded()
            XCTAssertEqual(panel.frame.width, expected.width, accuracy: 1)
            XCTAssertEqual(panel.frame.height, expected.height, accuracy: 1)
            XCTAssertEqual(hosting.frame.size, metrics.expandedSize)
        }
        state.isExpanded = false
        panel.setFrame(metrics.panelFrame(for: metrics.compactSize), display: false)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(panel.frame.size, metrics.compactSize)
        XCTAssertEqual(hosting.frame.size, metrics.compactSize)
    }
}
