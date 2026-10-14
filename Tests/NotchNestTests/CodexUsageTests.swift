import XCTest
@testable import NotchNest

final class CodexUsageTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testFindsCurrentAndLegacyBundledHelpers() {
        let app = URL(fileURLWithPath: "/Custom/ChatGPT.app")
        for suffix in ["Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
                       "Contents/Resources/codex"] {
            let expected = app.appendingPathComponent(suffix)
            XCTAssertEqual(CodexUsageRequest.executableURL(apps: [app],
                isExecutable: { $0 == expected.path }), expected)
        }
    }

    func testMissingHelpersAndCommandLineFallback() {
        XCTAssertNil(CodexUsageRequest.executableURL(apps: [], isExecutable: { _ in false }))
        let expected = URL(fileURLWithPath: "/opt/homebrew/bin/codex")
        XCTAssertEqual(CodexUsageRequest.executableURL(apps: [],
            isExecutable: { $0 == expected.path }), expected)
    }

    private func decode(_ json: String) throws -> WeeklyUsage {
        try CodexUsageDecoder.decode(Data(json.utf8), now: now)
    }

    func testWeeklyPrimaryAndRemainingNotUsed() throws {
        let usage = try decode("""
        {"rateLimits":{"primary":{"usedPercent":45,"windowDurationMins":10080,"resetsAt":1800086400}}}
        """)
        XCTAssertEqual(usage.remainingPercent, 55)
        XCTAssertEqual(usage.remainingLabel, "55%")
        XCTAssertEqual(usage.fetchedAt, now)
        XCTAssertEqual(usage.resetsAt, now.addingTimeInterval(86400))
    }

    func testFindsWeeklySecondaryInsteadOfSessionLimit() throws {
        let usage = try decode("""
        {"rateLimits":{"primary":{"usedPercent":99,"windowDurationMins":300},
        "secondary":{"usedPercent":12,"windowDurationMins":10080}}}
        """)
        XCTAssertEqual(usage.remainingPercent, 88)
        XCTAssertEqual(usage.session?.remainingPercent, 1)
    }

    func testMultiBucketTakesPrecedence() throws {
        let usage = try decode("""
        {"rateLimits":{"primary":{"usedPercent":99,"windowDurationMins":10080}},
        "rateLimitsByLimitId":{
        "codex_other":{"primary":{"usedPercent":80,"windowDurationMins":10080}},
        "codex":{"limitId":"codex","primary":{"usedPercent":25,"windowDurationMins":10080}}}}
        """)
        XCTAssertEqual(usage.remainingPercent, 75)
    }

    func testSubscriptionTierComesFromTheCodexBucket() throws {
        let usage = try decode("""
        {"rateLimits":{"planType":"plus","primary":{"usedPercent":99,"windowDurationMins":10080}},
        "rateLimitsByLimitId":{"codex":{"planType":"pro","primary":{"usedPercent":25,"windowDurationMins":10080}}}}
        """)
        XCTAssertEqual(usage.planType, "pro")
        XCTAssertEqual(usage.planLabel, "Pro")
    }

    func testMissingSubscriptionTierIsNotGuessed() throws {
        let usage = try decode("""
        {"rateLimits":{"primary":{"usedPercent":0,"windowDurationMins":10080}}}
        """)
        XCTAssertNil(usage.planLabel)
        XCTAssertNil(CodexUsageDecoder.accountPlan(Data(#"{"account":null}"#.utf8)))
        XCTAssertNil(CodexUsageDecoder.accountPlan(Data(#"{"account":{"type":"apiKey"}}"#.utf8)))
        XCTAssertEqual(CodexUsageDecoder.accountPlan(Data(#"{"account":{"type":"chatgpt","email":"fixture@example.com","planType":"plus"}}"#.utf8)), "plus")
    }

    func testDoesNotUseUnrelatedBucket() {
        XCTAssertThrowsError(try decode("""
        {"rateLimitsByLimitId":{"codex_other":{"primary":{"usedPercent":0,"windowDurationMins":10080}}}}
        """))
    }

    func testNoWeeklyIsNotZeroUsage() {
        for json in ["{}", "{\"rateLimits\":null}",
                     "{\"rateLimits\":{\"primary\":{\"usedPercent\":0,\"windowDurationMins\":300}}}",
                     "{\"rateLimits\":{\"primary\":{\"usedPercent\":null,\"windowDurationMins\":10080}}}"] {
            XCTAssertThrowsError(try decode(json))
        }
    }

    func testZeroIsValidAndNoResetIsHonest() throws {
        let usage = try decode("""
        {"rateLimits":{"primary":{"usedPercent":0,"windowDurationMins":10080,"resetsAt":null}}}
        """)
        XCTAssertEqual(usage.remainingPercent, 100)
        XCTAssertNil(usage.resetsAt)
        XCTAssertEqual(usage.countdown(at: now), "Time unavailable")
        XCTAssertFalse(usage.resetIsDue(at: now))
    }

    func testClampsOutOfRangeUsageAndRejectsInvalidReset() throws {
        for (used, expected) in [(110, 0.0), (-10, 100.0)] {
            let usage = try decode("""
            {"rateLimits":{"primary":{"usedPercent":\(used),"windowDurationMins":10080,"resetsAt":0}}}
            """)
            XCTAssertEqual(usage.remainingPercent, expected)
            XCTAssertNil(usage.resetsAt)
        }
    }

    func testCountdownBoundariesAndNoInventedRefill() {
        for (seconds, expected) in [(93720.0, "1d 2h"), (3600, "1h 0m"), (61, "2m"),
                                    (1, "1m"), (0, "Reset due"), (-60, "Reset due")] {
            let usage = WeeklyUsage(usedPercent: 90, resetsAt: now.addingTimeInterval(seconds), fetchedAt: now)
            XCTAssertEqual(usage.countdown(at: now), expected)
            XCTAssertEqual(usage.resetIsDue(at: now), seconds <= 0)
            XCTAssertEqual(usage.remainingPercent, 10)
        }
    }

    func testNearExhaustionDoesNotLookLikeOnePercent() {
        let usage = WeeklyUsage(usedPercent: 99.2, resetsAt: nil, fetchedAt: now)
        XCTAssertEqual(usage.remainingLabel, "<1%")
    }

    func testProLiteTierHasAReadableLabel() {
        let usage = WeeklyUsage(usedPercent: 0, resetsAt: nil, fetchedAt: now, planType: "prolite")
        XCTAssertEqual(usage.planLabel, "Pro Lite")
    }

    func testSmallRPCMessagesDoNotWaitForPipeBufferToFill() throws {
        let script = #"""
        IFS= read -r request
        case "$request" in *'"initialize"'*) ;; *) exit 1 ;; esac
        printf '%s\n' '{"id":0,"result":{}}'
        IFS= read -r initialized
        IFS= read -r request
        case "$request" in *'account/rateLimits/read'*) ;; *) exit 1 ;; esac
        printf '%s\n' '{"id":1,"result":{"rateLimits":{"planType":"pro","primary":{"usedPercent":45,"windowDurationMins":10080}}}}'
        exec /bin/sleep 5
        """#
        let began = Date()
        let usage = try CodexUsageRequest().run(executable: URL(fileURLWithPath: "/bin/sh"),
                                               timeout: 2, arguments: ["-c", script])
        XCTAssertEqual(usage.remainingPercent, 55)
        XCTAssertEqual(usage.planLabel, "Pro")
        XCTAssertLessThan(Date().timeIntervalSince(began), 2)
    }

    func testAccountReadSuppliesTierWithoutRefreshingCredentials() throws {
        let script = #"""
        IFS= read -r request
        printf '%s\n' '{"id":0,"result":{}}'
        IFS= read -r initialized
        IFS= read -r request
        printf '%s\n' '{"id":1,"result":{"rateLimits":{"primary":{"usedPercent":45,"windowDurationMins":10080}}}}'
        IFS= read -r request
        case "$request" in *'"account/read"'*) ;; *) exit 1 ;; esac
        case "$request" in *'"refreshToken":false'*) ;; *) exit 1 ;; esac
        printf '%s\n' '{"id":2,"result":{"account":{"type":"chatgpt","planType":"plus"}}}'
        """#
        let usage = try CodexUsageRequest().run(executable: URL(fileURLWithPath: "/bin/sh"),
                                               timeout: 2, arguments: ["-c", script])
        XCTAssertEqual(usage.planLabel, "Plus")
        XCTAssertEqual(usage.remainingPercent, 55)
    }

    func testAccountReadFailureDoesNotBreakWeeklyUsage() throws {
        let script = #"""
        IFS= read -r request
        printf '%s\n' '{"id":0,"result":{}}'
        IFS= read -r initialized
        IFS= read -r request
        printf '%s\n' '{"id":1,"result":{"rateLimits":{"primary":{"usedPercent":45,"windowDurationMins":10080}}}}'
        IFS= read -r request
        printf '%s\n' '{"id":2,"error":{"code":-32601,"message":"Not available"}}'
        """#
        let usage = try CodexUsageRequest().run(executable: URL(fileURLWithPath: "/bin/sh"),
                                               timeout: 2, arguments: ["-c", script])
        XCTAssertNil(usage.planLabel)
        XCTAssertEqual(usage.remainingPercent, 55)
    }

    func testUnresponsiveHelperTimesOut() {
        let began = Date()
        XCTAssertThrowsError(try CodexUsageRequest().run(
            executable: URL(fileURLWithPath: "/bin/sleep"), timeout: 0.1, arguments: ["5"])) { error in
            guard case CodexUsageError.timedOut = error else { return XCTFail("Expected timeout, got \(error)") }
        }
        XCTAssertLessThan(Date().timeIntervalSince(began), 1.5)
    }

    func testInFlightHelperCanBeCancelled() {
        let request = CodexUsageRequest()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { request.cancel() }
        let began = Date()
        XCTAssertThrowsError(try request.run(executable: URL(fileURLWithPath: "/bin/sleep"),
                                             timeout: 5, arguments: ["5"])) { error in
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertLessThan(Date().timeIntervalSince(began), 1.5)
    }

    func testExitedHelperFailsWithoutHanging() {
        XCTAssertThrowsError(try CodexUsageRequest().run(
            executable: URL(fileURLWithPath: "/usr/bin/false"), timeout: 1)) { error in
            guard case CodexUsageError.disconnected = error else { return XCTFail("Expected disconnection") }
        }
    }

    @MainActor
    func testFreshSnapshotDoesNotLaunchHelper() async {
        var calls = 0
        let usage = WeeklyUsage(usedPercent: 45, resetsAt: now.addingTimeInterval(86400), fetchedAt: now)
        let service = CodexUsageService(usage: usage) { calls += 1; return usage }
        await service.refresh(now: now.addingTimeInterval(299))
        XCTAssertEqual(calls, 0)
        await service.refresh(now: now.addingTimeInterval(300))
        XCTAssertEqual(calls, 1)
    }

    @MainActor
    func testForceRefreshAndRetryThrottle() async {
        var calls = 0
        let usage = WeeklyUsage(usedPercent: 45, resetsAt: nil, fetchedAt: now)
        let service = CodexUsageService(usage: usage) { calls += 1; throw CodexUsageError.disconnected }
        await service.refresh(force: true, now: now)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(service.usage, usage)
        XCTAssertNotNil(service.message)
        XCTAssertFalse(service.isLoading)
        await service.refresh(now: now.addingTimeInterval(30))
        XCTAssertEqual(calls, 1)
        await service.refresh(now: now.addingTimeInterval(60))
        XCTAssertEqual(calls, 2)
    }

    @MainActor
    func testResetDueRequestsNewReadingEvenWhenCacheYoung() async {
        var calls = 0
        let old = WeeklyUsage(usedPercent: 99, resetsAt: now, fetchedAt: now.addingTimeInterval(-30))
        let new = WeeklyUsage(usedPercent: 2, resetsAt: now.addingTimeInterval(604800), fetchedAt: now)
        let service = CodexUsageService(usage: old) { calls += 1; return new }
        await service.refresh(now: now)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(service.usage, new)
    }

    @MainActor
    func testCancellationDoesNotPresentAnError() async {
        let service = CodexUsageService { throw CancellationError() }
        await service.refresh(now: now)
        XCTAssertNil(service.message)
        XCTAssertNil(service.usage)
        XCTAssertFalse(service.isLoading)
    }

    @MainActor
    func testSuccessClearsOldError() async {
        var calls = 0
        let usage = WeeklyUsage(usedPercent: 1, resetsAt: nil, fetchedAt: now)
        let service = CodexUsageService {
            calls += 1
            if calls == 1 { throw CodexUsageError.timedOut }
            return usage
        }
        await service.refresh(force: true, now: now)
        XCTAssertNotNil(service.message)
        await service.refresh(force: true, now: now)
        XCTAssertNil(service.message)
        XCTAssertEqual(service.usage, usage)
    }
}
