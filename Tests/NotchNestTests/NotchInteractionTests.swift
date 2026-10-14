import AppKit
import XCTest
@testable import NotchNest

@MainActor
final class NotchInteractionTests: XCTestCase {
    private final class Pointer { var point = CGPoint(x: -10000, y: -10000) }
    private let metrics = NotchMetrics(notchWidth: 185, notchHeight: 32,
        screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982))

    private func fixture() -> (NotchState, NotchPresentation, Pointer) {
        _ = NSApplication.shared
        let state = NotchState(metrics: metrics, menuBarApps: MenuBarAppsService(preview: []))
        state.disableLiveRefresh = true
        let pointer = Pointer()
        let presentation = NotchPresentation(state: state, pointerLocation: { pointer.point }, closeDelay: 0.012)
        presentation.panel.isReleasedWhenClosed = false
        presentation.show(on: metrics)
        return (state, presentation, pointer)
    }

    private func move(_ point: CGPoint, pointer: Pointer, presentation: NotchPresentation) {
        pointer.point = point
        presentation.pointerMoved(to: point)
    }

    private var left: CGPoint { CGPoint(x: metrics.compactFrame.minX + 25, y: metrics.compactFrame.midY) }
    private var right: CGPoint { CGPoint(x: metrics.compactFrame.maxX - 25, y: metrics.compactFrame.midY) }
    private var outside: CGPoint { CGPoint(x: 200, y: 400) }

    func testBothWingsOpenWithoutAnEnterEventAndFullySizeTheWindow() async throws {
        let (state, presentation, pointer) = fixture()
        defer { presentation.hide(); presentation.panel.close() }
        for _ in 0..<5 {
            for point in [left, right] {
                move(point, pointer: pointer, presentation: presentation)
                XCTAssertTrue(state.isExpanded)
                XCTAssertEqual(presentation.panel.frame, metrics.panelFrame(for: metrics.expandedSize))
                move(outside, pointer: pointer, presentation: presentation)
                try await Task.sleep(for: .milliseconds(30))
                XCTAssertFalse(state.isExpanded)
                XCTAssertEqual(presentation.panel.frame.size, metrics.compactSize)
                XCTAssertEqual(presentation.panel.frame.midX, metrics.compactFrame.midX, accuracy: 0.75)
                XCTAssertEqual(presentation.panel.frame.maxY, metrics.compactFrame.maxY)
            }
        }
    }

    func testScreenTopEdgeOpensBothWings() {
        let (state, presentation, pointer) = fixture()
        defer { presentation.hide(); presentation.panel.close() }
        for x in [left.x, right.x, metrics.compactFrame.midX] {
            presentation.close()
            move(CGPoint(x: x, y: metrics.screenFrame.maxY), pointer: pointer, presentation: presentation)
            XCTAssertTrue(state.isExpanded, "The topmost screen point must count as inside")
        }
    }

    func testPanelEventUsesItsPositionRatherThanALaterCursorReading() {
        let (state, presentation, pointer) = fixture()
        defer { presentation.hide(); presentation.panel.close() }
        pointer.point = outside
        presentation.panel.onPointerChange?(left)
        XCTAssertTrue(state.isExpanded)
        XCTAssertEqual(presentation.panel.frame.size, metrics.expandedSize)
    }

    func testNearbyNativeIconsAndOldExpandedAreaDoNotOpenTheClosedNotch() {
        let (state, presentation, pointer) = fixture()
        defer { presentation.hide(); presentation.panel.close() }
        for point in [CGPoint(x: metrics.compactFrame.minX - 1, y: left.y),
                      CGPoint(x: metrics.compactFrame.maxX + 1, y: right.y),
                      CGPoint(x: metrics.screenFrame.midX, y: 800)] {
            move(point, pointer: pointer, presentation: presentation)
            XCTAssertFalse(state.isExpanded)
        }
    }

    func testFastEntryIntoTheCardAndSpuriousExitDoNotCollapseIt() async throws {
        let (state, presentation, pointer) = fixture()
        defer { presentation.hide(); presentation.panel.close() }
        move(left, pointer: pointer, presentation: presentation)
        move(CGPoint(x: 970, y: 750), pointer: pointer, presentation: presentation)
        presentation.panel.onPointerChange?(pointer.point)
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertTrue(state.isExpanded)
        XCTAssertEqual(presentation.panel.frame, metrics.panelFrame(for: metrics.expandedSize))
    }

    func testRapidLeaveReenterCannotFinishWithAnOldSmallFrame() async throws {
        let (state, presentation, pointer) = fixture()
        defer { presentation.hide(); presentation.panel.close() }
        for _ in 0..<30 {
            move(left, pointer: pointer, presentation: presentation)
            move(outside, pointer: pointer, presentation: presentation)
            move(right, pointer: pointer, presentation: presentation)
        }
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(state.isExpanded)
        XCTAssertEqual(presentation.panel.frame.size, metrics.expandedSize)
    }

    func testOutsideMovementDoesNotKeepRestartingTheCloseDeadline() async throws {
        let (state, presentation, pointer) = fixture()
        defer { presentation.hide(); presentation.panel.close() }
        move(left, pointer: pointer, presentation: presentation)
        for _ in 0..<8 {
            move(outside, pointer: pointer, presentation: presentation)
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertFalse(state.isExpanded)
    }

    func testBluetoothToastDoesNotTrapTheLargeCardOpen() async throws {
        let (state, presentation, pointer) = fixture()
        defer { presentation.hide(); presentation.panel.close() }
        move(left, pointer: pointer, presentation: presentation)
        state.btPopup = BTToast(device: BTDevice(address: "test", name: "AirPods", batteryMain: 80,
            batteryLeft: nil, batteryRight: nil, batteryCase: nil, minorType: "Headphones"), kind: .connected)
        move(outside, pointer: pointer, presentation: presentation)
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertFalse(state.isExpanded)
        XCTAssertEqual(presentation.panel.frame.size, metrics.toastSize)
    }

    func testDrawerIsPinnedForMouseAndShortcutAndEscapeStaysClosed() async throws {
        let (state, presentation, pointer) = fixture()
        defer { presentation.hide(); presentation.panel.close() }
        move(left, pointer: pointer, presentation: presentation)
        state.showingMenuBarApps = true // The same state change as the toolbar button.
        move(outside, pointer: pointer, presentation: presentation)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(state.isExpanded)
        presentation.close()
        presentation.openMenuBarApps()
        XCTAssertTrue(state.isExpanded)
        pointer.point = left
        presentation.close()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertFalse(state.isExpanded)
        XCTAssertFalse(state.showingMenuBarApps)
        move(right, pointer: pointer, presentation: presentation)
        XCTAssertTrue(state.isExpanded)
        XCTAssertEqual(presentation.panel.onMenuBarShortcut == nil, state.menuBarApps.shortcutAvailable)
    }

    func testMenuHandoffRecoversHoverWithoutASecondEnterEvent() async throws {
        let (state, presentation, pointer) = fixture()
        defer { presentation.hide(); presentation.panel.close() }
        presentation.openMenuBarApps()
        let item = MenuBarAppItem(id: "unavailable", appName: "Example", label: "Example", icon: nil,
            visibility: .visible, frame: nil, element: nil, pid: 0)
        state.menuBarApps.select(item)
        XCTAssertFalse(presentation.panel.isVisible)
        pointer.point = right
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(presentation.panel.isVisible)
        XCTAssertTrue(state.isExpanded)
        XCTAssertEqual(presentation.panel.frame.size, metrics.expandedSize)
    }

    func testDisplayPauseCancelsAQueuedNativeMenuAndHover() async throws {
        let (state, presentation, pointer) = fixture()
        defer { presentation.hide(); presentation.panel.close() }
        presentation.openMenuBarApps()
        state.menuBarApps.select(MenuBarAppItem(id: "cancel", appName: "Example", label: "Example", icon: nil,
            visibility: .visible, frame: nil, element: nil, pid: 0))
        presentation.hide()
        move(left, pointer: pointer, presentation: presentation)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertFalse(presentation.panel.isVisible)
        XCTAssertFalse(state.isExpanded)
        XCTAssertNil(state.alert)
        presentation.show(on: metrics)
        XCTAssertTrue(state.isExpanded, "Resume rechecks the pointer already on a wing")
    }

    func testHUDAndAlertsDoNotResizeAnExpandedTab() async throws {
        let (state, presentation, pointer) = fixture()
        defer { presentation.hide(); presentation.panel.close() }
        move(right, pointer: pointer, presentation: presentation)
        for tab in NotchTab.allCases {
            state.tab = tab
            state.hud = HUDInfo(kind: .volume, value: 0.5)
            state.alert = AlertToast(symbol: "timer", title: "Test", subtitle: "", tint: .orange)
            try await Task.sleep(for: .milliseconds(10))
            XCTAssertTrue(state.isExpanded)
            XCTAssertEqual(presentation.panel.frame.size, metrics.expandedSize)
        }
        move(outside, pointer: pointer, presentation: presentation)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(presentation.panel.frame.size, metrics.hudSize)
        state.hud = nil
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(presentation.panel.frame.size, metrics.toastSize)
        state.alert = nil
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(presentation.panel.frame.size, metrics.compactSize)
    }
}
