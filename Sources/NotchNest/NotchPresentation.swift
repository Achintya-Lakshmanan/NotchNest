import AppKit
import SwiftUI
import Combine

/// Owns the window and its interaction lifecycle. Hover is determined from
/// screen coordinates, not from enter/exit flags that a resize can invalidate.
@MainActor
final class NotchPresentation {
    let panel: NotchPanel
    private let state: NotchState
    private let pointerLocation: () -> CGPoint
    private let closeDelay: TimeInterval
    private let debug: Bool
    private var active = false
    private var closeWork: DispatchWorkItem?
    private var menuWork: DispatchWorkItem?
    private var menuGeneration = 0
    private var handingOffMenu = false
    private var trackingMenus = Set<ObjectIdentifier>()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private let shortcut = MenuBarShortcut()

    init(state: NotchState, pointerLocation: @escaping () -> CGPoint = { NSEvent.mouseLocation },
         closeDelay: TimeInterval = 0.24, debug: Bool = false) {
        self.state = state
        self.pointerLocation = pointerLocation
        self.closeDelay = closeDelay
        self.debug = debug
        panel = NotchPanel(metrics: state.metrics)
        if debug { panel.level = .floating }
        let hosting = NSHostingView(rootView: NotchRootView(state: state).environmentObject(state))
        panel.trackingHost.setContent(hosting)
        panel.onPointerChange = { [weak self] in self?.pointerMoved(to: $0) }
        panel.onEscape = { [weak self] in self?.close() }
        let toggle: () -> Void = { [weak self] in self?.toggleMenuBarApps() }
        state.menuBarApps.shortcutAvailable = shortcut.register(toggle)
        // A key must go through Carbon OR the panel fallback, never both.
        panel.onMenuBarShortcut = state.menuBarApps.shortcutAvailable ? nil : toggle
        state.menuBarApps.onSelect = { [weak self] in self?.openNativeMenu($0) }
        observeState()
        for name in [NSMenu.didBeginTrackingNotification, NSMenu.didEndTrackingNotification] {
            NotificationCenter.default.publisher(for: name)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] notification in
                    guard let self, self.active, let menu = notification.object as? NSMenu else { return }
                    let id = ObjectIdentifier(menu)
                    if name == NSMenu.didBeginTrackingNotification {
                        self.trackingMenus.insert(id)
                        self.cancelClose()
                    } else {
                        self.trackingMenus.remove(id)
                        self.checkPointer()
                    }
                }
                .store(in: &cancellables)
        }
    }

    func show(on metrics: NotchMetrics) {
        state.metrics = metrics
        active = true
        if debug { state.isExpanded = true }
        installPointerMonitors()
        relayout()
        panel.orderFrontRegardless()
        checkPointer()
    }

    func hide() {
        active = false
        cancelClose()
        menuGeneration += 1
        menuWork?.cancel()
        menuWork = nil
        handingOffMenu = false
        trackingMenus.removeAll()
        removePointerMonitors()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { state.dismissTransientPresentation() }
        panel.orderOut(nil)
    }

    func openPreferences() {
        guard active, !handingOffMenu else { return }
        cancelClose()
        state.showingMenuBarApps = false
        state.showingPreferences = true
        setExpanded(true)
    }

    func openMenuBarApps() {
        guard active, !handingOffMenu else { return }
        cancelClose()
        state.showingPreferences = false
        state.showingMenuBarApps = true
        setExpanded(true)
        panel.makeKeyAndOrderFront(nil)
    }

    func toggleMenuBarApps() {
        if state.showingMenuBarApps { close() }
        else { openMenuBarApps() }
    }

    func close() {
        cancelClose()
        setExpanded(false)
    }

    /// Also used by window tracking and tests. Moving into the intended card
    /// keeps it open even before the drawing transition has finished.
    func pointerMoved(to point: CGPoint) {
        guard active, panel.isVisible, !handingOffMenu, !debug else { return }
        let inside = state.isExpanded
            ? state.metrics.containsHover(point, presentedFrame: state.metrics.panelFrame(for: state.metrics.expandedSize))
            : state.metrics.isInCompactHoverArea(point)
        if inside {
            cancelClose()
            if !state.isHovering { state.isHovering = true }
            setExpanded(true)
        } else {
            if state.isHovering { state.isHovering = false }
            guard state.isExpanded, !state.showingMenuBarApps, trackingMenus.isEmpty,
                  NSApp.modalWindow == nil, closeWork == nil else { return }
            // Outside movements do not restart this deadline indefinitely.
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.closeWork = nil
                guard self.active, !self.handingOffMenu, !self.state.showingMenuBarApps,
                      self.trackingMenus.isEmpty, NSApp.modalWindow == nil else { return }
                let current = self.pointerLocation()
                if self.state.metrics.containsHover(current, presentedFrame: self.state.metrics.panelFrame(for: self.state.metrics.expandedSize)) {
                    self.pointerMoved(to: current)
                } else {
                    self.setExpanded(false)
                }
            }
            closeWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + closeDelay, execute: work)
        }
    }

    private func checkPointer() { pointerMoved(to: pointerLocation()) }

    private func cancelClose() {
        closeWork?.cancel()
        closeWork = nil
    }

    private func setExpanded(_ expanded: Bool) {
        guard active else { return }
        if state.isExpanded != expanded {
            if expanded {
                withAnimation(.easeOut(duration: 0.18)) { state.isExpanded = true }
            } else {
                // Do not leave the old large view animating inside a tiny window.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    state.isExpanded = false
                    state.isHovering = false
                    state.showingPreferences = false
                    state.showingMenuBarApps = false
                }
            }
        }
        relayout()
    }

    private func observeState() {
        state.$isExpanded.removeDuplicates().receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.relayout() }.store(in: &cancellables)
        state.$hud.map { $0 != nil }.removeDuplicates().receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.relayout() }.store(in: &cancellables)
        state.$btPopup.map { $0 != nil }.removeDuplicates().receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.relayout() }.store(in: &cancellables)
        state.$alert.map { $0 != nil }.removeDuplicates().receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.relayout() }.store(in: &cancellables)
    }

    private func relayout() {
        guard active else { return }
        let frame = state.metrics.panelFrame(for: state.presentationSize, centeredForDebug: debug)
        // Native hit geometry changes once. SwiftUI animates the content, so
        // an older NSWindow animation cannot later shrink an open card.
        let current = panel.frame
        // AppKit can round half-point origins. Do not resize on every pointer
        // event just because it aligned the same window to a screen pixel.
        if current.size != frame.size || abs(current.minX - frame.minX) > 0.75 || abs(current.minY - frame.minY) > 0.75 {
            panel.setFrame(frame, display: true)
        }
    }

    private func installPointerMonitors() {
        guard globalMonitor == nil, localMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .leftMouseDown, .rightMouseDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            let click = event.type == .leftMouseDown || event.type == .rightMouseDown
            let point = NSEvent.mouseLocation
            Task { @MainActor in self?.pointerEvent(at: point, isClick: click) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            let click = event.type == .leftMouseDown || event.type == .rightMouseDown
            let point = event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
            Task { @MainActor in self?.pointerEvent(at: point, isClick: click) }
            return event
        }
    }

    private func pointerEvent(at point: CGPoint, isClick: Bool) {
        if isClick, state.showingMenuBarApps, trackingMenus.isEmpty,
           !state.metrics.containsHover(point, presentedFrame: panel.frame) {
            close()
        } else {
            pointerMoved(to: point)
        }
    }

    private func removePointerMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func openNativeMenu(_ item: MenuBarAppItem) {
        guard active else { return }
        close()
        handingOffMenu = true
        menuGeneration += 1
        let generation = menuGeneration
        panel.orderOut(nil)
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.active, self.menuGeneration == generation else { return }
            self.state.menuBarApps.press(item) { [weak self] opened in
                guard let self, self.active, self.menuGeneration == generation else { return }
                self.menuWork = nil
                self.handingOffMenu = false
                self.relayout()
                self.panel.orderFrontRegardless()
                if !opened {
                    self.state.showAlert(AlertToast(symbol: "menubar.rectangle", title: "Menu unavailable",
                        subtitle: "\(item.appName) didn't allow its menu to open. Try its app or Refresh.", tint: .orange))
                }
                // Recover even if the mouse never emits another enter event.
                self.checkPointer()
            }
        }
        menuWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    deinit {
        closeWork?.cancel()
        menuWork?.cancel()
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }
}
