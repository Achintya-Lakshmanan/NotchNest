import AppKit
import XCTest
@testable import NotchNest

final class MenuBarAppsTests: XCTestCase {
    private let display = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let notch = CGRect(x: 656, y: 0, width: 200, height: 37)

    func testOnlyActualNotchOverlapCountsAsCovered() {
        XCTAssertEqual(classify(CGRect(x: 800, y: 0, width: 24, height: 37)), .covered)
        XCTAssertEqual(classify(CGRect(x: 640, y: 0, width: 24, height: 37)), .covered)
        XCTAssertEqual(classify(CGRect(x: 500, y: 0, width: 24, height: 37)), .visible)
        XCTAssertEqual(classify(CGRect(x: 856, y: 0, width: 24, height: 37)), .visible)
        XCTAssertEqual(classify(CGRect(x: 750, y: 100, width: 24, height: 37)), .visible)
    }

    func testMissingOrZeroFramesAreUnknownRatherThanDiscarded() {
        XCTAssertEqual(classify(nil), .unknown)
        XCTAssertEqual(classify(.zero), .unknown)
    }

    func testOffscreenAndExternalDisplayItems() {
        XCTAssertEqual(classify(CGRect(x: -30, y: 0, width: 24, height: 37)), .offscreen)
        let tv = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        XCTAssertEqual(MenuBarItemVisibility.classify(frame: CGRect(x: -1900, y: -200, width: 24, height: 30),
                                                      notch: notch, displays: [display, tv]), .visible)
    }

    func testAccessibilityCoordinateConversionWithExternalPrimaryDisplay() {
        let laptop = CGRect(x: -1512, y: 2160, width: 1512, height: 982)
        XCTAssertEqual(MenuBarAppsService.axRect(laptop, primaryTop: 2160),
                       CGRect(x: -1512, y: -982, width: 1512, height: 982))
    }

    func testSystemItemsUseTheirOwnLabelsInsteadOfRepeatedAppNames() {
        XCTAssertEqual(MenuBarAppsService.itemLabel(appName: "Control Center", title: "Wi-Fi, connected", multiple: true), "Wi-Fi")
        XCTAssertEqual(MenuBarAppsService.itemLabel(appName: "Example", title: "10 unread", multiple: false), "Example")
        XCTAssertEqual(MenuBarAppsService.itemLabel(appName: "Example", title: nil, multiple: false), "Example")
        XCTAssertEqual(MenuBarAppsService.itemLabel(appName: "MenuBarAgent", title: "Bluetooth, On", multiple: false), "Bluetooth")
    }

    func testAppsAndMacOSHelpersAreSeparate() {
        for name in ["MenuBarAgent", "Control Center", "SystemUIServer", "TextInputMenuAgent", "WeatherMenu"] {
            XCTAssertEqual(MenuBarSection.forApplication(name: name, bundleID: nil), .system)
        }
        XCTAssertEqual(MenuBarSection.forApplication(name: "Outlook", bundleID: "com.microsoft.Outlook"), .apps)
        XCTAssertEqual(MenuBarSection.forApplication(name: "Menu bar app", bundleID: "com.apple.Spotlight"), .system)
        XCTAssertEqual(MenuBarAppsService.itemLabel(appName: "MenuBarAgent", title: nil, multiple: true,
            identifier: "com.apple.menuextra.wifi"), "Wi-Fi")
        XCTAssertEqual(MenuBarAppsService.itemLabel(appName: "MenuBarAgent", title: "MenuBarAgent", multiple: true,
            index: 3), "System item 4")
    }

    func testExpandedAndPopupFramesHaveBlackSpaceBehindCutout() {
        for origin in [CGPoint.zero, CGPoint(x: -1512, y: -500), CGPoint(x: 100, y: 2160)] {
            let screen = CGRect(origin: origin, size: CGSize(width: 1512, height: 982))
            let metrics = NotchMetrics(notchWidth: 200, notchHeight: 37, screenFrame: screen)
            for size in [metrics.expandedSize, metrics.toastSize, metrics.hudSize] {
                let frame = metrics.panelFrame(for: size)
                XCTAssertEqual(frame.maxY, screen.maxY)
                XCTAssertTrue(screen.contains(frame))
            }
            XCTAssertEqual(metrics.panelFrame(for: metrics.compactSize).maxY, screen.maxY)
        }
    }

    @MainActor
    func testDisplayPauseClosesDrawer() {
        let state = NotchState(metrics: NotchMetrics(notchWidth: 200, notchHeight: 37, screenFrame: display))
        state.showingMenuBarApps = true
        state.isExpanded = true
        state.dismissTransientPresentation()
        XCTAssertFalse(state.showingMenuBarApps)
        XCTAssertFalse(state.isExpanded)
    }

    private func classify(_ frame: CGRect?) -> MenuBarItemVisibility {
        .classify(frame: frame, notch: notch, displays: [display])
    }
}
