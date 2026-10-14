import AppKit
import Combine
import Darwin

/// Only the allowance metadata is retained, never credentials or conversations.
struct WeeklyUsage: Equatable {
    let usedPercent: Double
    let resetsAt: Date?
    let fetchedAt: Date
    var planType: String? = nil
    /// The rolling five-hour session window, when the provider reports one.
    var session: SessionWindow? = nil

    struct SessionWindow: Equatable {
        let usedPercent: Double
        /// nil when no session is in progress (the window starts with the next message).
        let resetsAt: Date?

        var remainingPercent: Double { max(0, min(100, 100 - usedPercent)) }
        var remainingLabel: String {
            remainingPercent > 0 && remainingPercent < 1 ? "<1%" : "\(Int(remainingPercent.rounded(.down)))%"
        }
        func resetIsDue(at now: Date) -> Bool { resetsAt.map { $0 <= now } ?? false }
    }

    var planLabel: String? {
        guard let value = planType?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        if value.lowercased() == "api" { return "API" }
        if value.lowercased() == "prolite" { return "Pro Lite" }
        return value.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ").capitalized
    }

    var remainingPercent: Double { max(0, min(100, 100 - usedPercent)) }
    var remainingLabel: String {
        // Don't round a nearly exhausted allowance up to a whole percent.
        remainingPercent > 0 && remainingPercent < 1 ? "<1%" : "\(Int(remainingPercent.rounded(.down)))%"
    }

    func resetIsDue(at now: Date) -> Bool { resetsAt.map { $0 <= now } ?? false }

    func countdown(at now: Date) -> String { Self.countdown(to: resetsAt, at: now) }

    static func countdown(to resetsAt: Date?, at now: Date) -> String {
        guard let resetsAt else { return "Time unavailable" }
        let seconds = resetsAt.timeIntervalSince(now)
        guard seconds > 0 else { return "Reset due" }
        let minutes = Int(ceil(seconds / 60))
        if minutes >= 1440 { return "\(minutes / 1440)d \((minutes % 1440) / 60)h" }
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        return "\(minutes)m"
    }
}

enum CodexUsageError: Error, LocalizedError {
    case notInstalled, unavailable, noWeeklyWindow, timedOut, disconnected

    var errorDescription: String? {
        switch self {
        case .notInstalled: return "Install ChatGPT or Codex to connect your allowance."
        case .unavailable: return "Open Codex and check your sign-in, then retry."
        case .noWeeklyWindow: return "No weekly Codex allowance was returned for this account."
        case .timedOut: return "Codex took too long to respond. Try again shortly."
        case .disconnected: return "Couldn't reach Codex. Open it and try again."
        }
    }
}

enum CodexUsageDecoder {
    private struct Response: Decodable {
        var rateLimits: Bucket?
        var rateLimitsByLimitId: [String: Bucket]?
    }
    private struct Bucket: Decodable {
        var limitId: String?
        var planType: String?
        var primary: Window?
        var secondary: Window?
    }
    private struct Window: Decodable {
        var usedPercent: Double?
        var windowDurationMins: Int?
        var resetsAt: Double?
    }

    static func decode(_ data: Data, now: Date = Date()) throws -> WeeklyUsage {
        let response = try JSONDecoder().decode(Response.self, from: data)
        // The account-wide Codex bucket takes precedence over the legacy view.
        // Never silently substitute a model-specific bucket or a five-hour limit.
        let bucket: Bucket?
        if let buckets = response.rateLimitsByLimitId, !buckets.isEmpty {
            bucket = buckets["codex"]
        } else {
            bucket = response.rateLimits
        }
        guard let bucket, bucket.limitId == nil || bucket.limitId == "codex",
              let weekly = [bucket.primary, bucket.secondary].compactMap({ $0 })
                .first(where: { $0.windowDurationMins == 7 * 24 * 60 }),
              let used = weekly.usedPercent, used.isFinite else {
            throw CodexUsageError.noWeeklyWindow
        }
        func date(_ value: Double?) -> Date? {
            value.flatMap { $0.isFinite && $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
        }
        let session = [bucket.primary, bucket.secondary].compactMap({ $0 })
            .first(where: { $0.windowDurationMins == 5 * 60 })
            .flatMap { window -> WeeklyUsage.SessionWindow? in
                guard let used = window.usedPercent, used.isFinite else { return nil }
                return .init(usedPercent: max(0, min(100, used)), resetsAt: date(window.resetsAt))
            }
        return WeeklyUsage(usedPercent: max(0, min(100, used)), resetsAt: date(weekly.resetsAt),
                           fetchedAt: now, planType: bucket.planType, session: session)
    }

    static func accountPlan(_ data: Data) -> String? {
        struct AccountResponse: Decodable {
            struct Account: Decodable { var type: String; var planType: String? }
            var account: Account?
        }
        guard let account = try? JSONDecoder().decode(AccountResponse.self, from: data).account,
              account.type == "chatgpt" else { return nil }
        return account.planType
    }
}

@MainActor
final class CodexUsageService: ObservableObject {
    @Published private(set) var usage: WeeklyUsage?
    @Published private(set) var isLoading = false
    @Published private(set) var message: String?
    private var lastAttempt: Date?
    private let fetch: () async throws -> WeeklyUsage

    init(usage: WeeklyUsage? = nil,
         fetch: @escaping () async throws -> WeeklyUsage = { try await CodexUsageRequest.fetch() }) {
        self.usage = usage
        self.fetch = fetch
    }

    /// Called only by the visible Codex pane. No startup/background polling.
    func refresh(force: Bool = false, now: Date = Date()) async {
        // A quick close/reopen can overlap cancellation of the previous fetch.
        // Wait for cleanup so the reopened pane doesn't sit empty for a minute.
        while isLoading {
            do { try await Task.sleep(for: .milliseconds(50)) }
            catch { return }
        }
        guard !Task.isCancelled else { return }
        if !force {
            if let lastAttempt, now.timeIntervalSince(lastAttempt) < 60 { return }
            if message == nil, let usage, now.timeIntervalSince(usage.fetchedAt) < 300,
               !usage.resetIsDue(at: now) { return }
        }
        lastAttempt = now
        isLoading = true
        defer { isLoading = false }
        do {
            let updated = try await fetch()
            try Task.checkCancellation()
            usage = updated
            message = nil
        } catch is CancellationError {
            lastAttempt = nil
        } catch {
            if Task.isCancelled { lastAttempt = nil; return }
            message = (error as? CodexUsageError)?.errorDescription ?? "Usage is temporarily unavailable. Try again."
        }
    }
}

/// Short-lived, documented JSON-RPC connection. Codex manages its own sign-in;
/// NotchNest never opens auth.json, starts a thread, or consumes reset credits.
final class CodexUsageRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    static func executableURL() -> URL? {
        let workspace = NSWorkspace.shared
        let apps = [workspace.urlForApplication(withBundleIdentifier: "com.openai.codex"),
                    workspace.urlForApplication(withBundleIdentifier: "com.openai.chat"),
                    URL(fileURLWithPath: "/Applications/ChatGPT.app"),
                    URL(fileURLWithPath: "/Applications/Codex.app")].compactMap { $0 }
        return executableURL(apps: apps)
    }

    static func executableURL(apps: [URL],
                              isExecutable: (String) -> Bool = FileManager.default.isExecutableFile(atPath:)) -> URL? {
        let candidates = apps.flatMap { app in
            ["Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
             "Contents/Resources/codex"].map { app.appendingPathComponent($0) }
        } + [
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex")
        ]
        return candidates.first { isExecutable($0.path) }
    }

    static func fetch() async throws -> WeeklyUsage {
        guard let executable = executableURL() else { throw CodexUsageError.notInstalled }
        let request = CodexUsageRequest()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    do { continuation.resume(returning: try request.run(executable: executable)) }
                    catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: {
            request.cancel()
        }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    private func checkCancellation() throws {
        lock.lock()
        let value = cancelled
        lock.unlock()
        if value { throw CancellationError() }
    }

    // Blocking I/O lives on a utility queue, with a bounded deadline and a
    // cancellation check every 200 ms. No worker remains after the pane closes.
    func run(executable: URL, timeout: TimeInterval = 15,
             arguments: [String] = ["app-server", "--stdio"]) throws -> WeeklyUsage {
        try checkCancellation()
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        try process.run()
        defer {
            try? input.fileHandleForWriting.close()
            try? output.fileHandleForReading.close()
            if process.isRunning {
                process.terminate()
                // Escalate only for this owned helper if it ignores SIGTERM.
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
                    if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
                }
            }
        }

        func send(_ object: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])
            data.append(0x0A)
            try input.fileHandleForWriting.write(contentsOf: data)
        }
        try send(["id": 0, "method": "initialize", "params": ["clientInfo": [
            "name": "notchnest", "title": "NotchNest", "version": "1.0"
        ]]])

        var buffer = Data()
        var initialized = false
        var pendingUsage: WeeklyUsage?
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
        while ProcessInfo.processInfo.systemUptime < deadline {
            try checkCancellation()
            let ready = Darwin.poll(&descriptor, 1, 200)
            if ready < 0 {
                if errno == EINTR { continue }
                throw CodexUsageError.disconnected
            }
            guard ready > 0 else { continue }
            // FileHandle.read(upToCount:) may wait to fill the requested length
            // on a pipe. A single POSIX read returns the currently available
            // JSON-RPC bytes, preserving both the deadline and cancellation.
            var bytes = [UInt8](repeating: 0, count: 16_384)
            let count = Darwin.read(descriptor.fd, &bytes, bytes.count)
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else {
                if let pendingUsage { return pendingUsage }
                throw CodexUsageError.disconnected
            }
            buffer.append(contentsOf: bytes.prefix(count))
            guard buffer.count < 1_048_576 else { throw CodexUsageError.unavailable }
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer.prefix(upTo: newline)
                buffer.removeSubrange(...newline)
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let id = object["id"] as? Int else { continue }
                if object["error"] != nil {
                    // Plan metadata is optional. A failed account read must not
                    // hide an otherwise valid weekly limit.
                    if id == 2, let pendingUsage { return pendingUsage }
                    throw CodexUsageError.unavailable
                }
                if id == 0 && !initialized {
                    initialized = true
                    try send(["method": "initialized", "params": [:]])
                    try send(["id": 1, "method": "account/rateLimits/read"])
                } else if id == 1, initialized, let result = object["result"] as? [String: Any] {
                    let usage = try CodexUsageDecoder.decode(JSONSerialization.data(withJSONObject: result))
                    if usage.planLabel != nil { return usage }
                    pendingUsage = usage
                    try send(["id": 2, "method": "account/read", "params": ["refreshToken": false]])
                } else if id == 2, var usage = pendingUsage {
                    if let result = object["result"] as? [String: Any] {
                        usage.planType = CodexUsageDecoder.accountPlan(try JSONSerialization.data(withJSONObject: result))
                    }
                    return usage
                }
            }
        }
        if let pendingUsage { return pendingUsage }
        throw CodexUsageError.timedOut
    }
}
