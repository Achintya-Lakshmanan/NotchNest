import AppKit
import CoreGraphics

/// A value snapshot, not a retained NSScreen: coordinates can change on any
/// hot-plug, resolution, mirroring, or main-display change.
struct NotchDisplaySnapshot {
    var id: CGDirectDisplayID
    var isBuiltIn: Bool
    var isActive: Bool
    var isMirrored: Bool
    var frame: CGRect
    var notchHeight: CGFloat
    var leftSafeWidth: CGFloat
    var rightSafeWidth: CGFloat
}

struct NotchDisplayTarget: Equatable {
    var id: CGDirectDisplayID
    var metrics: NotchMetrics
}

enum DisplayRouting {
    /// Only the physical, independently drawable MacBook notch is a valid home.
    /// Never fall back to NSScreen.main (which can be the TV).
    static func target(in displays: [NotchDisplaySnapshot]) -> NotchDisplayTarget? {
        guard let display = displays.first(where: {
            $0.isBuiltIn && $0.isActive && !$0.isMirrored &&
            $0.notchHeight > 0 && $0.frame.width > 0 && $0.frame.height > 0 &&
            $0.leftSafeWidth > 0 && $0.rightSafeWidth > 0
        }) else { return nil }

        return NotchDisplayTarget(id: display.id, metrics: NotchMetrics(
            notchWidth: max(display.frame.width - display.leftSafeWidth - display.rightSafeWidth, 180),
            notchHeight: display.notchHeight,
            screenFrame: display.frame))
    }

    @MainActor
    static func currentTarget() -> NotchDisplayTarget? {
        target(in: NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            let id = number.uint32Value
            return NotchDisplaySnapshot(
                id: id,
                isBuiltIn: CGDisplayIsBuiltin(id) != 0,
                isActive: CGDisplayIsActive(id) != 0,
                // Includes BOTH the source and destination of a mirror set.
                // A mirrored built-in screen omitted from NSScreen.screens also
                // correctly produces no target, rather than selecting the TV.
                isMirrored: CGDisplayIsInMirrorSet(id) != 0,
                frame: screen.frame,
                notchHeight: screen.safeAreaInsets.top,
                leftSafeWidth: screen.auxiliaryTopLeftArea?.width ?? 0,
                rightSafeWidth: screen.auxiliaryTopRightArea?.width ?? 0)
        })
    }
}
