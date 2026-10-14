import Carbon

/// A registered hotkey, not a keyboard listener. No typed text is observed.
@MainActor
final class MenuBarShortcut {
    private var hotkey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (() -> Void)?
    private static let signature: OSType = 0x4E4E4D42

    func register(_ action: @escaping () -> Void) -> Bool {
        self.action = action
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetEventDispatcherTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard id.signature == 0x4E4E4D42, id.id == 1 else { return OSStatus(eventNotHandledErr) }
            let shortcut = Unmanaged<MenuBarShortcut>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor [weak shortcut] in shortcut?.action?() }
            return noErr
        }, 1, &event, context, &handler)
        guard installed == noErr else { return false }
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_M), UInt32(controlKey | optionKey),
                                        id, GetEventDispatcherTarget(), 0, &hotkey)
        if status != noErr, let handler { RemoveEventHandler(handler); self.handler = nil }
        return status == noErr
    }

    deinit {
        if let hotkey { UnregisterEventHotKey(hotkey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
