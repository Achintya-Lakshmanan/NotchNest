import AppKit
import SwiftUI
import Combine

@MainActor
final class NotchController: NSObject {
    private var panel: NotchPanel?
    private var state: NotchState?
    private var statusItem: NSStatusItem?
    private var prefsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var mediaTimer: Timer?
    private var batteryTimer: Timer?
    private var collapseWork: DispatchWorkItem?
    private let hudController = HUDController()
    private var bluetoothEventMonitor: BluetoothEventMonitor?

    // Verification helper: render the expanded card centered & floating so it's
    // visible to screenshot tooling. Not used in normal operation.
    private let debug = ProcessInfo.processInfo.environment["NOTCHNEST_DEBUG"] == "1"

    func start() {
        let screen = notchScreen()
        let metrics = computeMetrics(for: screen)
        let state = NotchState(metrics: metrics)
        self.state = state

        let panel = NotchPanel(metrics: metrics)
        panel.onHoverChange = { [weak self] hovering in
            self?.handleHover(hovering)
        }
        self.panel = panel

        let root = NotchRootView(state: state).environmentObject(state)
        let hosting = NSHostingView(rootView: root)
        hosting.layer?.backgroundColor = .clear
        panel.trackingHost.setContent(hosting)

        if debug {
            panel.level = .floating
            state.isExpanded = true
        }

        relayout()
        panel.orderFrontRegardless()

        observeExpansion()
        setupTimers()
        setupStatusItem()

        NotificationCenter.default.addObserver(
            forName: .openPreferences, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.openPreferences() }
        }

        // HUD key tap (volume/brightness). Needs Accessibility permission.
        hudController.onEvent = { [weak self] kind, value in
            MainActor.assumeIsolated { self?.state?.showHUD(kind, value: value) }
        }
        startHUD(prompt: true, attemptsLeft: 40)

        // First fill.
        state.refreshNowPlaying()
        state.battery = BatteryMonitor.current()
        state.refreshCalendar()
        state.refreshWeather()
    }

    // MARK: Expansion

    /// Hover events can fire spuriously while the window animates its resize.
    /// Expand immediately, but debounce + verify the cursor before collapsing.
    private func handleHover(_ hovering: Bool) {
        collapseWork?.cancel()
        if hovering {
            state?.isHovering = true
            setExpanded(true)
        } else {
            let work = DispatchWorkItem { [weak self] in self?.collapseIfCursorOutside() }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
        }
    }

    private func collapseIfCursorOutside() {
        guard let panel else { return }
        // Still inside the (possibly resized) window? Treat as not a real exit.
        if panel.frame.contains(NSEvent.mouseLocation) { return }
        state?.isHovering = false
        setExpanded(false)
    }

    private func setExpanded(_ expanded: Bool) {
        guard let state, state.isExpanded != expanded else { return }
        // Don't collapse out from under an active Bluetooth popup.
        if !expanded && state.btPopup != nil { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) {
            state.isExpanded = expanded
        }
        // Let NotchBar (the menu bar manager) tuck items away while we're open.
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(expanded ? "com.notchbar.notchnest.expanded"
                                       : "com.notchbar.notchnest.collapsed"),
            object: nil, userInfo: nil, deliverImmediately: true)
    }

    private func observeExpansion() {
        // NOTE: @Published fires in willSet (before the property updates), so we
        // hop to the next main-loop tick before reading state in relayout().
        state?.$isExpanded
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.relayout() }
            .store(in: &cancellables)

        // Bluetooth toast resizes the window to a small banner.
        state?.$btPopup
            .map { $0 != nil }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.relayout() }
            .store(in: &cancellables)

        // HUD resizes to a compact pill.
        state?.$hud
            .map { $0 != nil }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.relayout() }
            .store(in: &cancellables)

        // Generic alert toast.
        state?.$alert
            .map { $0 != nil }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.relayout() }
            .store(in: &cancellables)
    }

    private func relayout() {
        guard let panel, let state else { return }
        let metrics = state.metrics
        let size: CGSize
        if state.isExpanded {
            size = metrics.expandedSize
        } else if state.hud != nil {
            size = metrics.hudSize
        } else if state.btPopup != nil || state.alert != nil {
            size = metrics.toastSize
        } else {
            size = metrics.compactSize
        }
        let frame = metrics.screenFrame
        let originX = frame.midX - size.width / 2
        let originY = debug ? (frame.midY - size.height / 2) : (frame.maxY - size.height)
        let target = CGRect(x: originX, y: originY, width: size.width, height: size.height)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.32
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            ctx.allowsImplicitAnimation = true
            panel.animator().setFrame(target, display: true)
        }
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
        mediaTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.state?.refreshNowPlaying() }
        }
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.state?.updateBattery(BatteryMonitor.current()) }
        }
        // Calendar refreshes less often.
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.state?.refreshCalendar() }
        }
        // Weather every 15 minutes.
        Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.state?.refreshWeather() }
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
        }
        pollBluetooth()
        Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollBluetooth() }
        }
    }

    // MARK: Status item (quit)

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "NotchNest")
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "NotchNest", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        let prefs = NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit NotchNest", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    /// Try to install the HUD key tap; retries until Accessibility is granted
    /// so the user doesn't have to relaunch after enabling it.
    private func startHUD(prompt: Bool, attemptsLeft: Int) {
        if hudController.start(promptForAccess: prompt) { return }
        guard attemptsLeft > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.startHUD(prompt: false, attemptsLeft: attemptsLeft - 1)
        }
    }

    @objc private func openPreferences() {
        if prefsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 360),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false)
            window.title = "NotchNest Preferences"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView())
            window.center()
            prefsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        prefsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: Screen / metrics

    private func notchScreen() -> NSScreen {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func computeMetrics(for screen: NSScreen) -> NotchMetrics {
        let frame = screen.frame
        let top = screen.safeAreaInsets.top
        let left = screen.auxiliaryTopLeftArea?.width ?? 0
        let right = screen.auxiliaryTopRightArea?.width ?? 0

        let hasNotch = top > 0 && (left > 0 || right > 0)
        let notchWidth = hasNotch ? max(frame.width - left - right, 180) : 200
        let notchHeight = hasNotch ? top : 32

        return NotchMetrics(notchWidth: notchWidth, notchHeight: notchHeight, screenFrame: frame)
    }
}

// MARK: - Panel

final class NotchPanel: NSPanel {
    let trackingHost: TrackingHostView
    var onHoverChange: ((Bool) -> Void)?

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
        level = .statusBar
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = trackingHost
        trackingHost.onHoverChange = { [weak self] in self?.onHoverChange?($0) }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Tracking host

/// Hosts the SwiftUI view and reports mouse enter/exit so the controller
/// can expand/collapse the panel.
final class TrackingHostView: NSView {
    var onHoverChange: ((Bool) -> Void)?
    private var hosted: NSView?

    func setContent(_ view: NSView) {
        hosted?.removeFromSuperview()
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: topAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        hosted = view
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) { onHoverChange?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChange?(false) }
}
