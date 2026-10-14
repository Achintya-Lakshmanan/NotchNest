import AppKit
import Combine
import WebKit

enum ClaudeUsageError: Error, LocalizedError {
    case signIn, unavailable, noWeeklyWindow

    var errorDescription: String? {
        switch self {
        case .signIn: return "Connect Claude to read your plan and weekly allowance."
        case .unavailable: return "Claude couldn't refresh. Check the connection and try again."
        case .noWeeklyWindow: return "Claude didn't return a weekly allowance for this account."
        }
    }
}

enum ClaudeUsageDecoder {
    private struct Response: Decodable {
        struct Window: Decodable { var utilization: Double?; var resets_at: String? }
        var seven_day: Window?
        var five_hour: Window?
        var planType: String?
        var error: String?
    }

    static func decode(_ data: Data, now: Date = Date()) throws -> WeeklyUsage {
        let response = try JSONDecoder().decode(Response.self, from: data)
        if response.error == "signIn" { throw ClaudeUsageError.signIn }
        if response.error != nil { throw ClaudeUsageError.unavailable }
        guard let weekly = response.seven_day, let used = weekly.utilization, used.isFinite else {
            throw ClaudeUsageError.noWeeklyWindow
        }
        let session = response.five_hour.flatMap { window -> WeeklyUsage.SessionWindow? in
            guard let used = window.utilization, used.isFinite else { return nil }
            return .init(usedPercent: max(0, min(100, used)), resetsAt: parseDate(window.resets_at))
        }
        return WeeklyUsage(usedPercent: max(0, min(100, used)), resetsAt: parseDate(weekly.resets_at),
                           fetchedAt: now, planType: response.planType, session: session)
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

@MainActor
final class ClaudeUsageService: ObservableObject {
    @Published private(set) var usage: WeeklyUsage?
    @Published private(set) var isLoading = false
    @Published private(set) var message: String?
    private var lastAttempt: Date?
    private lazy var client: ClaudeWebUsageClient = {
        let client = ClaudeWebUsageClient()
        client.onConnectionClosed = { [weak self] in
            Task { await self?.refresh(force: true) }
        }
        return client
    }()

    init(usage: WeeklyUsage? = nil) { self.usage = usage }

    func connect() { client.showConnection() }

    /// Only the selected, visible pane refreshes. No model calls or background polling.
    func refresh(force: Bool = false, now: Date = Date()) async {
        guard !isLoading, !Task.isCancelled else { return }
        if !force {
            if let lastAttempt, now.timeIntervalSince(lastAttempt) < (message == nil ? 60 : 300) { return }
            if message == nil, let usage, now.timeIntervalSince(usage.fetchedAt) < 300,
               !usage.resetIsDue(at: now) { return }
        }
        lastAttempt = now
        isLoading = true
        defer { isLoading = false }
        do {
            let updated = try await client.fetch()
            try Task.checkCancellation()
            usage = updated
            message = nil
        } catch is CancellationError {
            lastAttempt = nil
        } catch {
            if Task.isCancelled { lastAttempt = nil; return }
            if let error = error as? ClaudeUsageError, case .signIn = error { usage = nil }
            message = (error as? ClaudeUsageError)?.errorDescription ?? ClaudeUsageError.unavailable.errorDescription
        }
    }
}

/// A separate first-party web sign-in. Cookies stay in WebKit's app-local store;
/// no browser database, Claude keychain entry, token, chat, or email is exported.
/// Claude's web usage routes are not a versioned public API, so failures remain
/// visible and never turn into fabricated zero usage.
@MainActor
private final class ClaudeWebUsageClient: NSObject, NSWindowDelegate {
    var onConnectionClosed: (() -> Void)?
    private var window: NSWindow?
    private var webView: WKWebView?
    private let usageURL = URL(string: "https://claude.ai/settings/usage")!
    private let connectionKey = "claudeWebConnectionStarted"

    private func browser() -> WKWebView {
        if let webView { return webView }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 660, height: 650), configuration: configuration)
        webView = view
        return view
    }

    func showConnection() {
        UserDefaults.standard.set(true, forKey: connectionKey)
        let view = browser()
        if window == nil {
            let window = NSWindow(contentRect: view.frame, styleMask: [.titled, .closable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "Connect Claude to NotchNest"
            window.isReleasedWhenClosed = false
            window.contentView = view
            window.delegate = self
            window.center()
            self.window = window
        }
        view.load(URLRequest(url: usageURL))
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        onConnectionClosed?()
    }

    func fetch() async throws -> WeeklyUsage {
        // Do not contact Claude before the user chooses Connect Claude.
        guard UserDefaults.standard.bool(forKey: connectionKey) else { throw ClaudeUsageError.signIn }
        // Release the hidden page after this reading. Claude's site must not
        // keep JavaScript timers running for the lifetime of the notch app.
        defer {
            if window?.isVisible != true {
                webView?.stopLoading()
                window?.contentView = nil
                window = nil
                webView = nil
            }
        }
        let view = browser()
        if window?.isVisible != true {
            view.load(URLRequest(url: usageURL))
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 20
        while view.isLoading {
            try Task.checkCancellation()
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw ClaudeUsageError.unavailable }
            try await Task.sleep(for: .milliseconds(100))
        }
        try Task.checkCancellation()
        guard view.url?.host == "claude.ai" else {
            UserDefaults.standard.set(false, forKey: connectionKey)
            throw ClaudeUsageError.signIn
        }
        let result: Any?
        do {
            result = try await view.callAsyncJavaScript(Self.readUsage, arguments: [:], in: nil, contentWorld: .page)
        } catch {
            throw ClaudeUsageError.signIn
        }
        try Task.checkCancellation()
        guard let json = result as? String else { throw ClaudeUsageError.unavailable }
        do {
            return try ClaudeUsageDecoder.decode(Data(json.utf8))
        } catch ClaudeUsageError.signIn {
            UserDefaults.standard.set(false, forKey: connectionKey)
            throw ClaudeUsageError.signIn
        }
    }

    // Read-only requests run on Claude's own origin. The bridge returns only the
    // all-model weekly and five-hour counters, reset timestamps, and explicitly reported plan.
    private static let readUsage = #"""
    const abort = new AbortController();
    const timeout = setTimeout(() => abort.abort(), 12000);
    const options = { credentials: 'same-origin', signal: abort.signal };
    try {
        const orgResponse = await fetch('/api/organizations', options);
        if (orgResponse.status === 401 || orgResponse.status === 403) return JSON.stringify({ error: 'signIn' });
        if (!orgResponse.ok) return JSON.stringify({ error: 'unavailable' });
        const orgs = await orgResponse.json();
        if (!Array.isArray(orgs) || orgs.length === 0) return JSON.stringify({ error: 'signIn' });
        const activeCookie = document.cookie.split('; ').find(part => part.startsWith('lastActiveOrg='));
        const active = activeCookie ? decodeURIComponent(activeCookie.slice('lastActiveOrg='.length)) : null;
        const org = orgs.find(item => item.uuid === active) || orgs[0];
        if (!org.uuid) return JSON.stringify({ error: 'unavailable' });
        const response = await fetch('/api/organizations/' + encodeURIComponent(org.uuid) + '/usage', options);
        if (response.status === 401 || response.status === 403) return JSON.stringify({ error: 'signIn' });
        if (!response.ok) return JSON.stringify({ error: 'unavailable' });
        const usage = await response.json();
        const capabilities = Array.isArray(org.capabilities) ? org.capabilities : [];
        const billing = typeof org.billing_type === 'string' ? org.billing_type.toLowerCase() : null;
        const knownPlans = ['free', 'pro', 'max', 'team', 'enterprise'];
        let plan = knownPlans.includes(billing) ? billing : null;
        if (!plan && capabilities.includes('claude_max')) plan = 'max';
        if (!plan && capabilities.includes('claude_pro')) plan = 'pro';
        return JSON.stringify({ seven_day: usage.seven_day ?? null, five_hour: usage.five_hour ?? null, planType: plan });
    } catch {
        return JSON.stringify({ error: 'unavailable' });
    } finally {
        clearTimeout(timeout);
    }
    """#
}
