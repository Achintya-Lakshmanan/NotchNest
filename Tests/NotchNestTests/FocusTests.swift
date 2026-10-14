import XCTest
@testable import NotchNest

final class FocusTests: XCTestCase {
    func testOnlyActualChangesProducePopups() {
        var changes = FocusChangeTracker()
        XCTAssertNil(changes.update(true)) // Already on at launch.
        XCTAssertNil(changes.update(true))
        XCTAssertEqual(changes.update(false), false)
        XCTAssertNil(changes.update(false))
        XCTAssertEqual(changes.update(true), true)
    }

    func testUnknownStatusAndWakeDoNotProduceFalseTransitions() {
        var changes = FocusChangeTracker()
        XCTAssertNil(changes.update(false))
        XCTAssertNil(changes.update(nil)) // Sharing revoked or unavailable.
        XCTAssertNil(changes.update(true))
        XCTAssertNil(changes.update(false, announce: false)) // Catch up after wake.
        XCTAssertEqual(changes.update(true), true)
    }
}
