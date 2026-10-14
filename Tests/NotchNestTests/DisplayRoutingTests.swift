import XCTest
import AppKit
@testable import NotchNest

final class DisplayRoutingTests: XCTestCase {
    private func laptop(frame: CGRect = CGRect(x: 0, y: 0, width: 1512, height: 982)) -> NotchDisplaySnapshot {
        NotchDisplaySnapshot(id: 1, isBuiltIn: true, isActive: true, isMirrored: false,
                             frame: frame, notchHeight: 37,
                             leftSafeWidth: (frame.width - 200) / 2,
                             rightSafeWidth: (frame.width - 200) / 2)
    }

    private func tv() -> NotchDisplaySnapshot {
        NotchDisplaySnapshot(id: 2, isBuiltIn: false, isActive: true, isMirrored: false,
                             frame: CGRect(x: 0, y: 0, width: 3840, height: 2160),
                             notchHeight: 0, leftSafeWidth: 0, rightSafeWidth: 0)
    }

    func testLaptopAloneUsesPhysicalNotch() throws {
        let target = try XCTUnwrap(DisplayRouting.target(in: [laptop()]))
        XCTAssertEqual(target.id, 1)
        XCTAssertEqual(target.metrics.notchWidth, 200)
        XCTAssertEqual(target.metrics.notchHeight, 37)
    }

    func testTVAsMainDisplayNeverWinsOverBuiltIn() throws {
        let screen = laptop(frame: CGRect(x: -1512, y: -200, width: 1512, height: 982))
        let target = try XCTUnwrap(DisplayRouting.target(in: [tv(), screen]))
        XCTAssertEqual(target.id, screen.id)
        XCTAssertEqual(target.metrics.screenFrame, screen.frame)
    }

    func testMirroredLaptopAsSourceHidesNotch() {
        var screen = laptop()
        screen.isMirrored = true
        XCTAssertNil(DisplayRouting.target(in: [screen, tv()]))
    }

    func testMirroredLaptopAsSecondaryHidesNotch() {
        var screen = laptop()
        screen.isMirrored = true
        screen.isActive = false
        XCTAssertNil(DisplayRouting.target(in: [tv(), screen]))
        // Some mirror configurations omit the secondary NSScreen altogether.
        XCTAssertNil(DisplayRouting.target(in: [tv()]))
    }

    func testClosedLidAndSleepingBuiltInHideNotch() {
        var screen = laptop()
        screen.isActive = false
        XCTAssertNil(DisplayRouting.target(in: [screen, tv()]))
        XCTAssertNil(DisplayRouting.target(in: []))
    }

    func testNoFakeNotchOnExternalOrNonNotchedScreens() {
        var fake = laptop()
        fake.isBuiltIn = false
        XCTAssertNil(DisplayRouting.target(in: [fake]))
        var plain = laptop()
        plain.notchHeight = 0
        XCTAssertNil(DisplayRouting.target(in: [plain]))
        plain = laptop()
        plain.leftSafeWidth = 0
        XCTAssertNil(DisplayRouting.target(in: [plain]))
    }

    func testUnrelatedExternalMirroringDoesNotHideIndependentLaptop() {
        var external = tv()
        external.isMirrored = true
        XCTAssertEqual(DisplayRouting.target(in: [external, laptop()])?.id, 1)
    }

    func testEveryPanelModeStaysAtLaptopTopForAllArrangements() throws {
        for origin in [CGPoint.zero, CGPoint(x: -1512, y: -500),
                       CGPoint(x: 3840, y: 0), CGPoint(x: 100, y: 2160)] {
            let screen = laptop(frame: CGRect(origin: origin, size: CGSize(width: 1512, height: 982)))
            let metrics = try XCTUnwrap(DisplayRouting.target(in: [tv(), screen])).metrics
            for size in [metrics.compactSize, metrics.expandedSize, metrics.hudSize, metrics.toastSize] {
                let frame = metrics.panelFrame(for: size)
                XCTAssertEqual(frame.midX, screen.frame.midX)
                XCTAssertEqual(frame.maxY, screen.frame.maxY)
                XCTAssertTrue(screen.frame.contains(frame))
            }
        }
    }

    func testResolutionAndScaleChangeUseNewPointGeometry() throws {
        let before = try XCTUnwrap(DisplayRouting.target(in: [laptop()]))
        var changed = laptop(frame: CGRect(x: -1800, y: 0, width: 1800, height: 1169))
        changed.notchHeight = 44
        changed.leftSafeWidth = 780
        changed.rightSafeWidth = 780
        let after = try XCTUnwrap(DisplayRouting.target(in: [tv(), changed]))
        XCTAssertNotEqual(before, after)
        XCTAssertEqual(after.metrics.notchWidth, 240)
        XCTAssertEqual(after.metrics.compactSize.height, 44)
        XCTAssertEqual(after.metrics.panelFrame(for: after.metrics.expandedSize).maxY, 1169)
    }

    func testConnectMirrorCloseLidDisconnectSequence() {
        let initial = DisplayRouting.target(in: [laptop()])
        let extended = DisplayRouting.target(in: [tv(), laptop()])
        var mirrored = laptop()
        mirrored.isMirrored = true
        XCTAssertEqual(initial, extended)
        XCTAssertNil(DisplayRouting.target(in: [mirrored, tv()]))
        XCTAssertNil(DisplayRouting.target(in: [tv()]))
        XCTAssertEqual(DisplayRouting.target(in: [laptop()]), initial)
    }

    func testStoppedHUDPassesMediaKeysThroughWithoutChangingAnything() throws {
        let hud = HUDController()
        var callbackCount = 0
        hud.onEvent = { _, _ in callbackCount += 1 }
        hud.brightnessDisplayID = 1
        hud.stop()
        hud.stop() // Suspend/resume notifications can arrive in bursts.
        XCTAssertFalse(hud.isRunning)
        XCTAssertNil(hud.brightnessDisplayID)
        for key in [0, 1, 2, 3, 7] {
            let event = try XCTUnwrap(NSEvent.otherEvent(
                with: .systemDefined, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, subtype: 8,
                data1: (key << 16) | 0x0A00, data2: 0)?.cgEvent)
            XCTAssertNotNil(hud.handle(event))
        }
        XCTAssertEqual(callbackCount, 0)
    }

    func testSuspendingPresentationPreservesTimerShelfAndTab() async {
        await MainActor.run {
            let state = NotchState(metrics: NotchMetrics(
                notchWidth: 200, notchHeight: 37,
                screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982)))
            state.tab = .timer
            state.timerRunning = true
            state.timerDuration = 1500
            state.timerRemaining = 315
            state.shelf = [ShelfItem(url: URL(fileURLWithPath: "/tmp/notchnest-display-test.txt"))]
            state.isExpanded = true
            state.isHovering = true
            state.showingPreferences = true
            state.hud = HUDInfo(kind: .volume, value: 0.5)
            state.alert = AlertToast(symbol: "timer", title: "Test", subtitle: "", tint: .orange)

            state.dismissTransientPresentation()

            XCTAssertTrue(state.timerRunning)
            XCTAssertEqual(state.timerRemaining, 315)
            XCTAssertEqual(state.timerDuration, 1500)
            XCTAssertEqual(state.shelf.count, 1)
            XCTAssertEqual(state.tab, .timer)
            XCTAssertFalse(state.isExpanded)
            XCTAssertFalse(state.isHovering)
            XCTAssertFalse(state.showingPreferences)
            XCTAssertNil(state.hud)
            XCTAssertNil(state.alert)
            XCTAssertNil(state.btPopup)
        }
    }
}
