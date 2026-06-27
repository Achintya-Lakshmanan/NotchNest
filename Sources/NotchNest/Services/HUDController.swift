import AppKit

// Media-key codes (from IOKit/hidsystem/ev_keymap.h — not exported to Swift).
private let kSoundUp = 0
private let kSoundDown = 1
private let kBrightnessUp = 2
private let kBrightnessDown = 3
private let kMute = 7

/// Intercepts the volume/brightness media keys, applies the change itself, and
/// reports it so the notch can show a HUD (suppressing the system overlay).
/// Requires Accessibility permission for the event tap to be created.
final class HUDController {
    var onEvent: ((HUDInfo.Kind, Double) -> Void)?
    fileprivate var tap: CFMachPort?
    private var source: CFRunLoopSource?

    /// Returns true if the tap was created (Accessibility granted).
    @discardableResult
    func start(promptForAccess: Bool) -> Bool {
        if promptForAccess {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
        }

        let mask = CGEventMask(1 << 14) // NSSystemDefined
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: hudTapCallback,
            userInfo: refcon
        ) else {
            return false
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    fileprivate func handle(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let passthrough = Unmanaged.passUnretained(event)
        guard let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else { return passthrough }

        let data1 = ns.data1
        let keyCode = Int((data1 & 0xFFFF_0000) >> 16)
        let keyFlags = data1 & 0x0000_FFFF
        let keyDown = ((keyFlags & 0xFF00) >> 8) == 0x0A
        guard keyDown else { return passthrough }   // act only on press

        switch keyCode {
        case kSoundUp, kSoundDown, kMute:
            adjustVolume(keyCode)
            return nil   // consume → no system HUD
        case kBrightnessUp, kBrightnessDown:
            if BrightnessControl.isAvailable {
                adjustBrightness(keyCode)
                return nil
            }
            // Can't set brightness ourselves; let the OS do it but mirror a HUD.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                if let b = BrightnessControl.get() { self?.onEvent?(.brightness, Double(b)) }
            }
            return passthrough
        default:
            return passthrough
        }
    }

    private func adjustVolume(_ keyCode: Int) {
        let step: Float = 1.0 / 16.0
        if keyCode == kMute {
            let muted = !AudioOutput.isMuted()
            AudioOutput.setMuted(muted)
            let v = Double(AudioOutput.volume() ?? 0)
            onEvent?(muted ? .muted : .volume, v)
            return
        }
        if AudioOutput.isMuted() { AudioOutput.setMuted(false) }
        var v = AudioOutput.volume() ?? 0
        v += (keyCode == kSoundUp ? step : -step)
        v = min(max(v, 0), 1)
        AudioOutput.setVolume(v)
        onEvent?(.volume, Double(v))
    }

    private func adjustBrightness(_ keyCode: Int) {
        let step: Float = 1.0 / 16.0
        var b = BrightnessControl.get() ?? 0.5
        b += (keyCode == kBrightnessUp ? step : -step)
        b = min(max(b, 0), 1)
        BrightnessControl.set(b)
        onEvent?(.brightness, Double(b))
    }
}

private func hudTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<HUDController>.fromOpaque(refcon).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = controller.tap { CGEvent.tapEnable(tap: tap, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    return controller.handle(event)
}
