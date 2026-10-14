import AppKit
import Intents

final class AppDelegate: NSObject, NSApplicationDelegate, INShareFocusStatusIntentHandling {
    private var controller: NotchController?

    func application(_ application: NSApplication, handlerFor intent: INIntent) -> Any? {
        intent is INShareFocusStatusIntent ? self : nil
    }

    func handle(intent: INShareFocusStatusIntent,
                completion: @escaping (INShareFocusStatusIntentResponse) -> Void) {
        Task { @MainActor in
            controller?.receiveFocusStatus(intent.focusStatus?.isFocused)
            completion(INShareFocusStatusIntentResponse(code: .success, userActivity: nil))
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Read-only integration smoke test; no window, model task, or account changes.
        if ProcessInfo.processInfo.environment["NOTCHNEST_CODEX_CHECK"] == "1" {
            Task { @MainActor in
                do {
                    let usage = try await CodexUsageRequest.fetch()
                    print("Codex plan: \(usage.planLabel ?? "unavailable"); weekly: \(usage.remainingLabel) left; reset: \(usage.resetsAt?.description ?? "unavailable")")
                } catch {
                    print("Codex usage check failed: \(error.localizedDescription)")
                }
                NSApp.terminate(nil)
            }
            return
        }
        if let artPath = ProcessInfo.processInfo.environment["NOTCHNEST_ARTTEST"] {
            MediaController().fetchMusicArtwork { image in
                if let image, let tiff = image.tiffRepresentation,
                   let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: artPath))
                    print("ART OK: \(image.size)")
                } else {
                    print("ART FAILED")
                }
                NSApp.terminate(nil)
            }
            return
        }
        if Snapshot.runIfRequested() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) }
            return
        }
        controller = NotchController()
        controller?.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
