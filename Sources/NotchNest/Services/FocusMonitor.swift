import AppKit
import Intents
import Security

/// Reads Apple's shared Focus status. An unknown status is never treated as off.
/// Focus changes arrive through KVO and INShareFocusStatusIntent. The controller
/// also refreshes on its existing battery tick; no new timer or helper process.
@MainActor
final class FocusMonitor: ObservableObject {
    let isAvailable: Bool
    @Published private(set) var authorization: INFocusStatusAuthorizationStatus
    private var observation: NSKeyValueObservation?
    private var wakeObserver: NSObjectProtocol?
    private var onChange: ((Bool) -> Void)?
    private var changes = FocusChangeTracker()

    init() {
        var code: SecStaticCode?
        var info: CFDictionary?
        let foundCode = SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &code)
        if foundCode == errSecSuccess, let code,
           SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
           let info = info as? [String: Any],
           let entitlements = info[kSecCodeInfoEntitlementsDict as String] as? [String: Any] {
            isAvailable = entitlements["com.apple.developer.usernotifications.communication"] as? Bool == true
        } else {
            isAvailable = false
        }
        authorization = isAvailable ? INFocusStatusCenter.default.authorizationStatus : .restricted
    }

    func start(onChange: @escaping (Bool) -> Void) {
        guard isAvailable else { return }
        self.onChange = onChange
        let center = INFocusStatusCenter.default
        observation = center.observe(\.focusStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh(announce: false) }
        }
        refresh(announce: false)
        if authorization == .notDetermined { requestAccess() }
    }

    func requestAccess() {
        guard isAvailable else { return }
        INFocusStatusCenter.default.requestAuthorization { [weak self] status in
            Task { @MainActor in
                self?.authorization = status
                self?.refresh(announce: false)
            }
        }
    }

    func refresh(announce: Bool = true) {
        guard isAvailable else { return }
        let center = INFocusStatusCenter.default
        authorization = center.authorizationStatus
        guard authorization == .authorized else { changes = FocusChangeTracker(); return }
        receive(center.focusStatus.isFocused, announce: announce)
    }

    func receive(_ focused: Bool?, announce: Bool = true) {
        guard isAvailable else { return }
        if let changed = changes.update(focused, announce: announce) { onChange?(changed) }
    }

    deinit {
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }
}

struct FocusChangeTracker {
    private var previous: Bool?

    mutating func update(_ focused: Bool?, announce: Bool = true) -> Bool? {
        let old = previous
        previous = focused
        guard let focused, let old, announce, old != focused else { return nil }
        return focused
    }
}
