import AppKit

enum AirDropService {
    /// Opens the system AirDrop picker for the given files.
    static func send(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        guard let service = NSSharingService(named: .sendViaAirDrop) else { return }
        // Bring the app forward so the AirDrop sheet is interactable.
        NSApp.activate(ignoringOtherApps: true)
        if service.canPerform(withItems: urls) {
            service.perform(withItems: urls)
        }
    }
}
