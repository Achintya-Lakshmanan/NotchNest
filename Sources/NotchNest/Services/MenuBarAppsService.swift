import AppKit
@preconcurrency import ApplicationServices
import Combine

enum MenuBarSection: String, CaseIterable {
    case apps = "Apps"
    case system = "System"

    static func forApplication(name: String, bundleID: String?) -> Self {
        let systemNames = ["MenuBarAgent", "Control Center", "SystemUIServer", "TextInputMenuAgent", "WeatherMenu"]
        return systemNames.contains(name) || bundleID == "com.apple.Spotlight" ? .system : .apps
    }
}

enum MenuBarItemVisibility: Equatable {
    case visible, covered, offscreen, unknown

    static func classify(frame: CGRect?, notch: CGRect?, displays: [CGRect]) -> Self {
        guard let frame, frame.width > 0, frame.height > 0 else { return .unknown }
        if let notch, frame.intersects(notch) { return .covered }
        if !displays.contains(where: { $0.contains(frame) }) { return .offscreen }
        return .visible
    }
}

struct MenuBarAppItem: Identifiable {
    let id: String
    let appName: String
    let label: String
    let icon: NSImage?
    let visibility: MenuBarItemVisibility
    let frame: CGRect?
    let element: AXUIElement?
    let pid: pid_t
    var section: MenuBarSection = .apps
}

/// Scans only when the drawer opens or Refresh is pressed. AX calls have a
/// short timeout and run off the main thread, including calls to background apps.
@MainActor
final class MenuBarAppsService: ObservableObject {
    @Published private(set) var items: [MenuBarAppItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasAccess = false
    @Published var shortcutAvailable = true
    var onSelect: ((MenuBarAppItem) -> Void)?
    private var generation = 0

    init(preview: [MenuBarAppItem]? = nil) {
        if let preview {
            items = preview
            hasAccess = true
        }
    }

    func refresh() {
        hasAccess = AXIsProcessTrusted()
        guard hasAccess, !isLoading else { return }
        generation += 1
        let request = generation
        isLoading = true
        let previewMode = ProcessInfo.processInfo.environment["NOTCHNEST_DEBUG"] == "1"
        let apps = NSWorkspace.shared.runningApplications.filter {
            previewMode || $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }.map { Application(pid: $0.processIdentifier, name: $0.localizedName ?? "Menu bar app",
                            icon: $0.icon, bundleID: $0.bundleIdentifier) }
        // Accessibility coordinates use a top-left origin on the primary screen.
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        let displays = NSScreen.screens.map { Self.axRect($0.frame, primaryTop: primaryTop) }
        let notch = DisplayRouting.currentTarget().map { target in
            let m = target.metrics
            return Self.axRect(CGRect(x: m.screenFrame.midX - m.notchWidth / 2,
                                      y: m.screenFrame.maxY - m.notchHeight,
                                      width: m.notchWidth, height: m.notchHeight), primaryTop: primaryTop)
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Self.scan(apps: apps, notch: notch, displays: displays)
            DispatchQueue.main.async {
                guard let self, self.generation == request else { return }
                self.items = result
                self.isLoading = false
            }
        }
    }

    func requestAccess() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        refresh()
    }

    func select(_ item: MenuBarAppItem) { onSelect?(item) }

    func press(_ item: MenuBarAppItem, completion: @escaping (Bool) -> Void) {
        guard let element = item.element else { completion(false); return }
        DispatchQueue.global(qos: .userInitiated).async {
            AXUIElementSetMessagingTimeout(element, 0.3)
            var names: CFArray?
            AXUIElementCopyActionNames(element, &names)
            let press = AXUIElementPerformAction(element, kAXPressAction as CFString)
            let show = press == .success ? AXError.success : AXUIElementPerformAction(element, kAXShowMenuAction as CFString)
            let opened = press == .success || show == .success
            if ProcessInfo.processInfo.environment["NOTCHNEST_DEBUG"] == "1" {
                NSLog("NotchNest menu action %@: press=%d show=%d actions=%@", item.label,
                      press.rawValue, show.rawValue, String(describing: names))
            }
            DispatchQueue.main.async { completion(opened) }
        }
    }

    nonisolated static func axRect(_ rect: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryTop - rect.maxY, width: rect.width, height: rect.height)
    }

    private struct Application {
        let pid: pid_t
        let name: String
        let icon: NSImage?
        let bundleID: String?
    }

    nonisolated private static func scan(apps: [Application], notch: CGRect?, displays: [CGRect]) -> [MenuBarAppItem] {
        var result: [MenuBarAppItem] = []
        for app in apps {
            let section = MenuBarSection.forApplication(name: app.name, bundleID: app.bundleID)
            let axApp = AXUIElementCreateApplication(app.pid)
            AXUIElementSetMessagingTimeout(axApp, 0.15)
            guard let ref = attribute(axApp, "AXExtrasMenuBar"),
                  CFGetTypeID(ref) == AXUIElementGetTypeID() else { continue }
            let bar = ref as! AXUIElement
            AXUIElementSetMessagingTimeout(bar, 0.15)
            guard let children = attribute(bar, kAXChildrenAttribute) as? [AXUIElement] else { continue }
            for (index, element) in children.enumerated() {
                AXUIElementSetMessagingTimeout(element, 0.15)
                let identifier = attribute(element, kAXIdentifierAttribute) as? String
                let title = menuTitle(element, ignoring: section == .system ? app.name : nil)
                let label = itemLabel(appName: app.name, title: title, multiple: children.count > 1,
                                      identifier: identifier, index: index)
                let frame = frameOf(element)
                result.append(MenuBarAppItem(id: "\(app.pid):\(identifier ?? String(index))",
                    appName: app.name, label: label, icon: app.icon,
                    visibility: .classify(frame: frame, notch: notch, displays: displays),
                    frame: frame, element: element, pid: app.pid, section: section))
            }
        }
        return result.sorted {
            if $0.visibility == .covered && $1.visibility != .covered { return true }
            if $1.visibility == .covered && $0.visibility != .covered { return false }
            return ($0.frame?.minX ?? .greatestFiniteMagnitude) < ($1.frame?.minX ?? .greatestFiniteMagnitude)
        }
    }

    nonisolated static func itemLabel(appName: String, title: String?, multiple: Bool,
                                     identifier: String? = nil, index: Int = 0) -> String {
        if appName == "MenuBarAgent", title == nil || title == appName {
            let key = identifier?.lowercased() ?? ""
            let labels = [("wifi", "Wi-Fi"), ("bluetooth", "Bluetooth"), ("battery", "Battery"),
                          ("clock", "Clock"), ("controlcenter", "Control Center"), ("airplay", "Screen Mirroring"),
                          ("focus", "Focus"), ("volume", "Sound"), ("spotlight", "Spotlight"),
                          ("siri", "Siri"), ("input", "Input Sources")]
            return labels.first(where: { key.contains($0.0) })?.1 ?? "System item \(index + 1)"
        }
        guard let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return appName }
        if multiple || appName == "Control Center" || appName == "SystemUIServer" || appName == "MenuBarAgent" {
            return String(title.prefix(while: { $0 != "," && $0 != "\n" })).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return appName
    }

    /// New macOS menu items sometimes put their label on a child image.
    nonisolated private static func menuTitle(_ element: AXUIElement, ignoring generic: String?, depth: Int = 0) -> String? {
        for name in [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute] {
            if let value = attribute(element, name) as? String {
                let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty, text != generic { return text }
            }
        }
        guard depth < 2, let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { return nil }
        for child in children.prefix(8) {
            AXUIElementSetMessagingTimeout(child, 0.15)
            if let title = menuTitle(child, ignoring: generic, depth: depth + 1) { return title }
        }
        return nil
    }

    nonisolated private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    nonisolated private static func frameOf(_ element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute),
              let size = attribute(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        let p = position as! AXValue
        let s = size as! AXValue
        guard AXValueGetType(p) == .cgPoint, AXValueGetType(s) == .cgSize else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(p, .cgPoint, &point), AXValueGetValue(s, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }
}
