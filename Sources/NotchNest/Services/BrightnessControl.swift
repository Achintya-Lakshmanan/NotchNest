import CoreGraphics
import Foundation

/// Reads/sets display brightness via the private DisplayServices framework.
/// May be unavailable on some setups — callers should check `isAvailable`.
enum BrightnessControl {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let handle = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)

    private static let getFn: GetFn? = handle
        .flatMap { dlsym($0, "DisplayServicesGetBrightness") }
        .map { unsafeBitCast($0, to: GetFn.self) }

    private static let setFn: SetFn? = handle
        .flatMap { dlsym($0, "DisplayServicesSetBrightness") }
        .map { unsafeBitCast($0, to: SetFn.self) }

    static var isAvailable: Bool { getFn != nil && setFn != nil }

    static func get(displayID: CGDirectDisplayID) -> Float? {
        var value: Float = 0
        if let getFn, getFn(displayID, &value) == 0 { return value }
        return nil
    }

    @discardableResult
    static func set(_ value: Float, displayID: CGDirectDisplayID) -> Bool {
        setFn?(displayID, min(max(value, 0), 1)) == 0
    }
}
