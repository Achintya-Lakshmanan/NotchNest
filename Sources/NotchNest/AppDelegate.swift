import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
