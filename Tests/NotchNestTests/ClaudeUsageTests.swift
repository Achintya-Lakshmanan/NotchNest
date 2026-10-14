import XCTest
@testable import NotchNest

final class ClaudeUsageTests: XCTestCase {
    func testAllModelWeeklyLimitAndTier() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let usage = try ClaudeUsageDecoder.decode(Data(#"{"seven_day":{"utilization":32.5,"resets_at":"2026-10-10T12:30:00.000Z"},"planType":"max"}"#.utf8), now: now)
        XCTAssertEqual(usage.remainingPercent, 67.5)
        XCTAssertEqual(usage.remainingLabel, "67%")
        XCTAssertEqual(usage.planLabel, "Max")
        XCTAssertEqual(usage.fetchedAt, now)
        XCTAssertEqual(usage.resetsAt, ISO8601DateFormatter().date(from: "2026-10-10T12:30:00Z"))
    }

    func testNoWeeklyLimitIsNeverShownAsZeroUsage() {
        for json in ["{}", #"{"seven_day":null}"#, #"{"seven_day":{"utilization":null}}"#,
                     #"{"five_hour":{"utilization":20},"seven_day_opus":{"utilization":50}}"#] {
            XCTAssertThrowsError(try ClaudeUsageDecoder.decode(Data(json.utf8)))
        }
    }

    func testMissingTierAndResetStayUnknown() throws {
        let usage = try ClaudeUsageDecoder.decode(Data(#"{"seven_day":{"utilization":0,"resets_at":"invalid"}}"#.utf8))
        XCTAssertEqual(usage.remainingPercent, 100)
        XCTAssertNil(usage.planLabel)
        XCTAssertNil(usage.resetsAt)
    }

    func testPercentIsClampedWithoutInventingAReset() throws {
        let usage = try ClaudeUsageDecoder.decode(Data(#"{"seven_day":{"utilization":120}}"#.utf8))
        XCTAssertEqual(usage.remainingPercent, 0)
        XCTAssertEqual(usage.countdown(at: Date()), "Time unavailable")
    }

    func testConnectionErrorsAreNotTreatedAsUsage() {
        XCTAssertThrowsError(try ClaudeUsageDecoder.decode(Data(#"{"error":"signIn"}"#.utf8))) { error in
            guard case ClaudeUsageError.signIn = error else { return XCTFail("Expected sign-in request") }
        }
        XCTAssertThrowsError(try ClaudeUsageDecoder.decode(Data(#"{"error":"unavailable"}"#.utf8))) { error in
            guard case ClaudeUsageError.unavailable = error else { return XCTFail("Expected unavailable reading") }
        }
    }

    func testFiveHourSessionWindow() throws {
        let usage = try ClaudeUsageDecoder.decode(Data(#"{"seven_day":{"utilization":10},"five_hour":{"utilization":42,"resets_at":"2026-10-10T12:30:00Z"}}"#.utf8))
        XCTAssertEqual(usage.session?.remainingPercent, 58)
        XCTAssertEqual(usage.session?.remainingLabel, "58%")
        XCTAssertEqual(usage.session?.resetsAt, ISO8601DateFormatter().date(from: "2026-10-10T12:30:00Z"))
    }

    func testIdleOrMissingSessionWindow() throws {
        let idle = try ClaudeUsageDecoder.decode(Data(#"{"seven_day":{"utilization":10},"five_hour":{"utilization":0,"resets_at":null}}"#.utf8))
        XCTAssertEqual(idle.session?.remainingPercent, 100)
        XCTAssertNil(idle.session?.resetsAt)
        let missing = try ClaudeUsageDecoder.decode(Data(#"{"seven_day":{"utilization":10},"five_hour":null}"#.utf8))
        XCTAssertNil(missing.session)
    }
}
