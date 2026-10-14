import AppKit
import XCTest
@testable import NotchNest

final class CompactNotchTests: XCTestCase {
    func testCollapsedNotchKeepsBothVisibleSides() {
        let metrics = NotchMetrics(notchWidth: 185, notchHeight: 32,
                                   screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982))
        XCTAssertEqual(metrics.compactFrame, CGRect(x: 607.5, y: 950, width: 297, height: 32))
        XCTAssertEqual(metrics.compactSize, CGSize(width: 297, height: 32))
    }

    func testBothSidesRemainHoverableAcrossDisplayOrigins() {
        for origin in [CGPoint.zero, CGPoint(x: -1512, y: -500), CGPoint(x: 200, y: 2160)] {
            let screen = CGRect(origin: origin, size: CGSize(width: 1512, height: 982))
            let metrics = NotchMetrics(notchWidth: 185, notchHeight: 32, screenFrame: screen)
            let frame = metrics.compactFrame
            XCTAssertEqual(frame.minX + 56, screen.midX - 92.5)
            XCTAssertEqual(frame.maxX - 56, screen.midX + 92.5)
            XCTAssertTrue(frame.contains(CGPoint(x: frame.minX + 10, y: frame.midY)))
            XCTAssertTrue(frame.contains(CGPoint(x: frame.maxX - 10, y: frame.midY)))
            XCTAssertFalse(frame.contains(CGPoint(x: frame.minX - 1, y: frame.midY)))
            XCTAssertFalse(frame.contains(CGPoint(x: frame.maxX + 1, y: frame.midY)))
            XCTAssertTrue(screen.contains(frame))
        }
    }

    func testExpandedPanelStaysAttachedAndKeepsOriginalContentHeight() {
        let metrics = NotchMetrics(notchWidth: 185, notchHeight: 32,
                                   screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982))
        let expanded = metrics.panelFrame(for: metrics.expandedSize)
        XCTAssertEqual(expanded.maxY, metrics.screenFrame.maxY)
        XCTAssertTrue(expanded.contains(metrics.compactFrame))
        XCTAssertEqual(expanded.height - metrics.notchHeight, 250)
    }

}
