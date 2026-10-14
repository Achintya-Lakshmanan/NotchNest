import AppKit
import SwiftUI
import Combine

@MainActor
final class NotchController: NSObject {
    private var presentation: NotchPresentation?
    private var state: NotchState?
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    private var mediaTimer: Timer?
    private var batteryTimer: Timer?
    private var calendarTimer: Timer?
    private var weatherTimer: Timer?
    private var bluetoothTimer: Timer?
    private let hudController = HUDController()
    private var bluetoothEventMonitor: BluetoothEventMonitor?
    private var downloadMonitor: DownloadMonitor?
    func receiveFocusStatus(_ focused: Bool?) { state?.focusMonitor.receive(focused) }
    /// Skip-count while nothing is playing so AppleScript isn't hammered idle.
    private var mediaIdleTicks = 0
    private var displayTarget: NotchDisplayTarget?
    private var displayRefresh: DisplayRefresh?
    private var hudRetryWork: DispatchWorkItem?
    private var hasRequestedHUDPermission = false
    private var displaysAsleep = false
    private var displayStatusItem: NSMenuItem?

    // Verification helper: render the expanded card centered & floating so it's
    // visible to screenshot tooling. Not used in normal operation.
    private let debug = ProcessInfo.processInfo.environment["NOTCHNEST_DEBUG"] == "1"

    func start() {
        let target = DisplayRouting.currentTarget()
        // Placeholder geometry is never displayed when no MacBook notch exists.
        let metrics = target?.metrics ?? NotchMetrics(notchWidth: 200, notchHeight: 32, screenFrame: .zero)
        let state = NotchState(metrics: metrics)
        self.state = state

        presentation = NotchPresentation(state: state, debug: debug)
        displayRefresh = DisplayRefresh(target: target, source: { DisplayRouting.currentTarget() }) { [weak self] in
            self?.applyDisplayTarget($0)
        }
        setupTimers()
        setupStatusItem()
        observeDisplays()

        // HUD key tap (volume/brightness). Needs Accessibility permission.
        // Event-tap callbacks are not guaranteed MainActor-isolated — hop explicitly.
        hudController.onEvent = { [weak self] kind, value in
            Task { @MainActor in
                guard let self, self.displayTarget != nil else { return }
                self.state?.showHUD(kind, value: value)
            }
        }
        hudController.onCapsLockChanged = { [weak self] enabled in
            Task { @MainActor in
                guard let self, self.displayTarget != nil,
                      Settings.shared.showSystemPopups else { return }
                self.state?.showAlert(AlertToast(symbol: "capslock.fill",
                    title: enabled ? "Caps Lock On" : "Caps Lock Off",
                    subtitle: enabled ? "Typing in uppercase" : "Normal typing",
                    tint: enabled ? .orange : .gray), duration: 2)
            }
        }
        applyDisplayTarget(target)
        state.focusMonitor.start { [weak self] enabled in
            guard let self, self.displayTarget != nil,
                  Settings.shared.showSystemPopups else { return }
            self.state?.showAlert(AlertToast(symbol: enabled ? "moon.fill" : "moon",
                title: enabled ? "Focus On" : "Focus Off",
                subtitle: enabled ? "Notifications silenced" : "Notifications resumed",
                tint: enabled ? .purple : .gray), duration: 2.5)
        }

        // First fill.
        state.refreshNowPlaying()
        state.battery = BatteryMonitor.current()
        state.refreshCalendar()
        state.refreshWeather()
    }

    private func pollBluetooth() {
        BluetoothMonitor.connectedDevices { [weak self] devices in
            Task { @MainActor in
                let connected = self?.bluetoothEventMonitor?.connectedAddresses ?? []
                self?.state?.updateBluetooth(devices, eventConnected: connected)
            }
        }
    }

    // MARK: Timers

    private func setupTimers() {
        mediaTimer = schedule(every: 2.0) { [weak self] in
            guard let self, let state = self.state else { return }
            // Idle backoff: poll ~every 10s when nothing is playing (AppleScript is costly).
            if state.nowPlaying == nil {
                self.mediaIdleTicks += 1
                if self.mediaIdleTicks < 5 { return }
                self.mediaIdleTicks = 0
            } else {
                self.mediaIdleTicks = 0
            }
            state.refreshNowPlaying()
        }
        batteryTimer = schedule(every: 8.0) { [weak self] in
            self?.state?.focusMonitor.refresh()
            // IOKit + SmartBattery registry reads stay off the main thread.
            DispatchQueue.global(qos: .utility).async {
                let info = BatteryMonitor.current()
                DispatchQueue.main.async { self?.state?.updateBattery(info) }
            }
        }
        calendarTimer = schedule(every: 60) { [weak self] in
            self?.state?.refreshCalendar()
        }
        weatherTimer = schedule(every: 900) { [weak self] in
            self?.state?.refreshWeather()
        }

        // Bluetooth: IOBluetooth for connect/disconnect toasts; system_profiler for battery/UI list.
        let btEvents = BluetoothEventMonitor()
        bluetoothEventMonitor = btEvents
        btEvents.start { [weak self] name, address, connected in
            if connected {
                self?.state?.bluetoothDidConnect(name: name, address: address)
            } else {
                self?.state?.bluetoothDidDisconnect(name: name, address: address)
            }
            // Fresh battery shortly after connect/disconnect.
            self?.pollBluetooth()
        }
        pollBluetooth()
        bluetoothTimer = schedule(every: 30) { [weak self] in
            // system_profiler is expensive — only while IOBluetooth reports a connection.
            // Expand alone is not a reason to spawn it (connect/disconnect already re-poll).
            guard let self else { return }
            let connected = self.bluetoothEventMonitor?.connectedAddresses ?? []
            if !connected.isEmpty {
                self.pollBluetooth()
            }
        }

        let dl = DownloadMonitor()
        downloadMonitor = dl
        dl.start(
            onUpdate: { [weak self] items in
                self?.state?.updateDownloads(items)
            },
            onFinished: { [weak self] name in
                self?.state?.downloadDidFinish(name: name)
            }
        )
    }

    /// Timer on `.common` so polling keeps working during tracking/scroll modes.
    @discardableResult
    private func schedule(every interval: TimeInterval, _ block: @escaping @MainActor () -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            Task { @MainActor in block() }
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    // MARK: Status item (quit)

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "NotchNest")
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "NotchNest", action: nil, keyEquivalent: ""))
        let displayStatus = NSMenuItem(title: "Waiting for MacBook display", action: nil, keyEquivalent: "")
        menu.addItem(displayStatus)
        displayStatusItem = displayStatus
        menu.addItem(.separator())
        let apps = NSMenuItem(title: "Menu bar apps", action: #selector(openMenuBarApps), keyEquivalent: "")
        apps.target = self
        menu.addItem(apps)
        let prefs = NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit NotchNest", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        // The notch already exposes Preferences and Quit. Keep a fallback icon
        // only while the MacBook display is unavailable.
        item.isVisible = displayTarget == nil
        statusItem = item
    }

    /// Try to install the HUD key tap; retries until Accessibility is granted
    /// so the user doesn't have to relaunch after enabling it.
    private func startHUD(prompt: Bool, attemptsLeft: Int) {
        hudRetryWork?.cancel()
        guard displayTarget != nil else { return }
        if hudController.start(promptForAccess: prompt) { return }
        guard attemptsLeft > 0 else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.startHUD(prompt: false, attemptsLeft: attemptsLeft - 1)
        }
        hudRetryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    @objc private func openPreferences() {
        presentation?.openPreferences()
    }

    // MARK: Menu bar drawer

    @objc private func openMenuBarApps() {
        presentation?.openMenuBarApps()
    }

    // MARK: Display changes

    private func observeDisplays() {
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleDisplayRefresh() }
            .store(in: &cancellables)

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            workspace.publisher(for: name)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.displaysAsleep = true
                    self?.scheduleDisplayRefresh()
                }
                .store(in: &cancellables)
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            workspace.publisher(for: name)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.displaysAsleep = false
                    self?.scheduleDisplayRefresh()
                }
                .store(in: &cancellables)
        }
    }

    private func scheduleDisplayRefresh() {
        displayRefresh?.refresh(displaysAsleep: displaysAsleep)
    }

    private func applyDisplayTarget(_ target: NotchDisplayTarget?) {
        guard let presentation else { return }
        statusItem?.isVisible = target == nil
        guard target != displayTarget else { return }
        hudRetryWork?.cancel()
        hudController.stop()
        displayTarget = nil // Block hover and queued HUD/layout callbacks while moving.
        presentation.hide()

        guard let target else {
            displayStatusItem?.title = "Paused — MacBook display unavailable or mirrored"
            return
        }
        displayTarget = target
        presentation.show(on: target.metrics)
        displayStatusItem?.title = "On MacBook display — auto-pauses for mirroring"
        hudController.brightnessDisplayID = target.id
        let prompt = !hasRequestedHUDPermission
        hasRequestedHUDPermission = true
        startHUD(prompt: prompt, attemptsLeft: 40)
    }
}

// MARK: - Panel

final class NotchPanel: NSPanel {
    let trackingHost: TrackingHostView
    var onPointerChange: ((CGPoint) -> Void)?
    var onEscape: (() -> Void)?
    var onMenuBarShortcut: (() -> Void)?

    init(metrics: NotchMetrics) {
        trackingHost = TrackingHostView()
        super.init(
            contentRect: CGRect(origin: .zero, size: metrics.compactSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false   // we draw the notch ourselves; no system shadow halo
        // Stay above native menu-bar hit testing, but below native popup menus.
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        acceptsMouseMovedEvents = true
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = trackingHost
        trackingHost.onPointerChange = { [weak self] in self?.onPointerChange?($0) }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 46,
           event.modifierFlags.intersection([.control, .option, .shift, .command]) == [.control, .option],
           let onMenuBarShortcut {
            onMenuBarShortcut()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - Tracking host

/// Hosts the SwiftUI view and reports mouse enter/exit so the controller
/// can expand/collapse the panel.
final class TrackingHostView: NSView {
    var onPointerChange: ((CGPoint) -> Void)?
    private var hosted: NSView?
    private var pointerTrackingArea: NSTrackingArea?

    func setContent<Content: View>(_ view: NSHostingView<Content>) {
        hosted?.removeFromSuperview()
        // The controller owns the panel's size. SwiftUI's default minimum / ideal
        // size constraints can otherwise grow the window when Calendar contains
        // both a flexible event list and the fixed-height reminder card.
        view.sizingOptions = []
        view.translatesAutoresizingMaskIntoConstraints = true
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
        addSubview(view)
        hosted = view
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // inVisibleRect follows bounds changes. Replacing the area every frame
        // can lose the enter event while the pointer is already over a wing.
        guard pointerTrackingArea == nil else { return }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        pointerTrackingArea = area
        addTrackingArea(area)
    }

    private func pointerChanged(_ event: NSEvent) {
        guard let window else { return }
        onPointerChange?(window.convertPoint(toScreen: event.locationInWindow))
    }

    override func mouseEntered(with event: NSEvent) { pointerChanged(event) }
    override func mouseExited(with event: NSEvent) { pointerChanged(event) }
    override func mouseMoved(with event: NSEvent) { pointerChanged(event) }
}
