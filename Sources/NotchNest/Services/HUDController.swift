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
    var onCapsLockChanged: ((Bool) -> Void)?
    var brightnessDisplayID: CGDirectDisplayID?
    fileprivate var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var runLoop: CFRunLoop?

    var isRunning: Bool { tap != nil }

    /// Suspend interception, not just the drawing: hidden notch UI must leave
    /// the normal macOS keys/HUD available during mirroring and TV-only use.
    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        tap = nil
        if let source, let runLoop {
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
        }
        source = nil
        runLoop = nil
        brightnessDisplayID = nil
    }

    deinit { stop() }

    /// Returns true if the tap was created (Accessibility granted).
    @discardableResult
    func start(promptForAccess: Bool) -> Bool {
        if tap != nil { return true }
        if promptForAccess {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
        }

        let mask = CGEventMask((1 << 14) | (1 << CGEventType.flagsChanged.rawValue))
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
        let runLoop = CFRunLoopGetCurrent()
        self.runLoop = runLoop
        CFRunLoopAddSource(runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func handle(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let passthrough = Unmanaged.passUnretained(event)
        guard isRunning else { return passthrough }
        if event.type == .flagsChanged {
            if event.getIntegerValueField(.keyboardEventKeycode) == 57 {
                onCapsLockChanged?(event.flags.contains(.maskAlphaShift))
            }
            return passthrough
        }
        guard let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else { return passthrough }

        let data1 = ns.data1
        let keyCode = Int((data1 & 0xFFFF_0000) >> 16)
        let keyFlags = data1 & 0x0000_FFFF
        let keyDown = ((keyFlags & 0xFF00) >> 8) == 0x0A
        guard keyDown else { return passthrough }   // act only on press

        switch keyCode {
        case kSoundUp, kSoundDown, kMute:
            // HDMI outputs often don't expose software volume. Don't swallow
            // keys and draw a fictitious level for an unsupported TV output.
            guard AudioOutput.volume() != nil else { return passthrough }
            adjustVolume(keyCode)
            return nil   // consume → no system HUD
        case kBrightnessUp, kBrightnessDown:
            return adjustBrightness(keyCode) ? nil : passthrough
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

    private func adjustBrightness(_ keyCode: Int) -> Bool {
        guard let displayID = brightnessDisplayID,
              var b = BrightnessControl.get(displayID: displayID) else { return false }
        let step: Float = 1.0 / 16.0
        b += (keyCode == kBrightnessUp ? step : -step)
        b = min(max(b, 0), 1)
        guard BrightnessControl.set(b, displayID: displayID) else { return false }
        onEvent?(.brightness, Double(b))
        return true
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
