import AppKit
import XCTest
@testable import NotchNest

@MainActor
final class DisplayRefreshTests: XCTestCase {
    private let laptop = NotchDisplayTarget(id: 1, metrics: NotchMetrics(notchWidth: 185, notchHeight: 32,
        screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982)))

    func testUnchangedDisplayPreservesTheOpenCard() async throws {
        var changes: [NotchDisplayTarget?] = []
        let refresh = DisplayRefresh(target: laptop, source: { self.laptop }, settleDelay: 0.01) { changes.append($0) }
        for _ in 0..<20 { refresh.refresh(displaysAsleep: false) }
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(refresh.target, laptop)
        XCTAssertTrue(changes.isEmpty)
    }

    func testRepeatedEmptySnapshotsDoNotCancelRecovery() async throws {
        var source: NotchDisplayTarget? = nil
        var changes: [NotchDisplayTarget?] = []
        let refresh = DisplayRefresh(target: laptop, source: { source }, settleDelay: 0.01) { changes.append($0) }
        refresh.refresh(displaysAsleep: false)
        refresh.refresh(displaysAsleep: false)
        refresh.refresh(displaysAsleep: false)
        XCTAssertNil(refresh.target)
        source = laptop
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(changes, [nil, laptop])
        XCTAssertEqual(refresh.target, laptop)
    }

    func testDelayedDisplayAvailabilityRecoversWithoutAnotherNotification() async throws {
        var source: NotchDisplayTarget? = nil
        var changes: [NotchDisplayTarget?] = []
        let refresh = DisplayRefresh(target: laptop, source: { source }, settleDelay: 0.02) { changes.append($0) }
        refresh.refresh(displaysAsleep: false)
        try await Task.sleep(for: .milliseconds(30))
        source = laptop
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(changes, [nil, laptop])
        XCTAssertEqual(refresh.target, laptop)
    }

    func testSleepCancelsRecoveryAndWakeRestartsIt() async throws {
        var changes: [NotchDisplayTarget?] = []
        let refresh = DisplayRefresh(target: laptop, source: { self.laptop }, settleDelay: 0.01) { changes.append($0) }
        refresh.refresh(displaysAsleep: true)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(changes, [nil])
        refresh.refresh(displaysAsleep: false)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(changes, [nil, laptop])
    }

    func testUnavailableDisplayRetriesAreBounded() async throws {
        var reads = 0
        let refresh = DisplayRefresh(target: laptop, source: { reads += 1; return nil },
                                     settleDelay: 0.01, maxAttempts: 3) { _ in }
        refresh.refresh(displaysAsleep: false)
        try await Task.sleep(for: .milliseconds(70))
        XCTAssertEqual(reads, 4)
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(reads, 4, "No permanent polling while the built-in screen is unavailable")
        XCTAssertNil(refresh.target)
    }
}
