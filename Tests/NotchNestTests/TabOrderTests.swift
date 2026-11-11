import XCTest
@testable import NotchNest

final class TabOrderTests: XCTestCase {
    func testNoSavedOrderKeepsDefault() {
        XCTAssertEqual(Settings.ordered([]), NotchTab.allCases)
    }

    func testSavedOrderComesFirstAndMissingTabsFollow() {
        let tabs = Settings.ordered(["Shelf", "Music"])
        XCTAssertEqual(Array(tabs.prefix(2)), [.shelf, .music])
        XCTAssertEqual(Set(tabs), Set(NotchTab.allCases))
        XCTAssertEqual(tabs.count, NotchTab.allCases.count)
    }

    func testUnknownAndRepeatedNamesAreIgnored() {
        let tabs = Settings.ordered(["Gone", "Timer", "Timer"])
        XCTAssertEqual(tabs.first, .timer)
        XCTAssertEqual(tabs.count, NotchTab.allCases.count)
    }
}
