import AppKit

// NotchNest runs as an accessory app: no Dock icon, lives in the notch.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Normally accessory (no Dock icon). Set NOTCHNEST_REGULAR=1 to run as a
// regular app — used only for screenshot/verification tooling.
app.setActivationPolicy(ProcessInfo.processInfo.environment["NOTCHNEST_REGULAR"] == "1" ? .regular : .accessory)
app.run()
