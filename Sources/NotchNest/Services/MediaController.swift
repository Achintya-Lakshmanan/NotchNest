import AppKit

/// Talks to Apple Music and Spotify via AppleScript. First use will prompt
/// for Automation permission per app (System Settings ▸ Privacy ▸ Automation).
final class MediaController {
    private let queue = DispatchQueue(label: "notchnest.media", qos: .userInitiated)

    // MARK: Detection

    private func isRunning(_ app: MediaApp) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == app.bundleID }
    }

    /// Prefer whichever player is actively playing; fall back to a running one.
    private func activeApp() -> MediaApp? {
        let candidates = [MediaApp.spotify, .music].filter { isRunning($0) }
        return candidates.first
    }

    // MARK: Fetch

    func fetch(completion: @escaping (NowPlaying?) -> Void) {
        queue.async {
            var result: NowPlaying?
            // Check both; a "playing" one wins over a merely-running one.
            for app in [MediaApp.spotify, .music] where self.isRunning(app) {
                if let np = self.query(app) {
                    if np.isPlaying { result = np; break }
                    if result == nil { result = np }
                }
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func query(_ app: MediaApp) -> NowPlaying? {
        let script: String
        switch app {
        case .spotify:
            script = """
            tell application "Spotify"
              if it is running then
                try
                  set t to current track
                  set out to (name of t) & "\\n" & (artist of t) & "\\n" & (album of t) & "\\n" & (player state as string) & "\\n" & (player position as string) & "\\n" & ((duration of t) / 1000) & "\\n" & (artwork url of t)
                  return out
                on error
                  return ""
                end try
              end if
            end tell
            """
        case .music:
            script = """
            tell application "Music"
              if it is running then
                try
                  set t to current track
                  set out to (name of t) & "\\n" & (artist of t) & "\\n" & (album of t) & "\\n" & (player state as string) & "\\n" & (player position as string) & "\\n" & (duration of t) & "\\n"
                  return out
                on error
                  return ""
                end try
              end if
            end tell
            """
        }

        guard let raw = run(script), !raw.isEmpty else { return nil }
        let parts = raw.components(separatedBy: "\n")
        guard parts.count >= 6 else { return nil }

        let state = parts[3].lowercased()
        let elapsed = Double(parts[4].trimmingCharacters(in: .whitespaces)) ?? 0
        let duration = Double(parts[5].trimmingCharacters(in: .whitespaces)) ?? 0
        let art = parts.count >= 7 ? parts[6].trimmingCharacters(in: .whitespaces) : nil

        return NowPlaying(
            app: app,
            title: parts[0],
            artist: parts[1],
            album: parts[2],
            isPlaying: state.contains("playing"),
            elapsed: elapsed,
            duration: duration,
            artworkURL: (art?.isEmpty == false) ? art : nil
        )
    }

    // MARK: Apple Music artwork (raw image data)

    func fetchMusicArtwork(completion: @escaping (NSImage?) -> Void) {
        queue.async {
            let script = """
            tell application "Music"
              if it is running then
                try
                  return (data of artwork 1 of current track)
                on error
                  return missing value
                end try
              end if
            end tell
            """
            var image: NSImage?
            if let s = NSAppleScript(source: script) {
                var error: NSDictionary?
                let desc = s.executeAndReturnError(&error)
                if error == nil {
                    let data = desc.data
                    if !data.isEmpty { image = NSImage(data: data) }
                }
            }
            DispatchQueue.main.async { completion(image) }
        }
    }

    // MARK: Transport

    func playPause(app: MediaApp?) { command("playpause", app: app) }
    func next(app: MediaApp?) { command("next track", app: app) }
    func previous(app: MediaApp?) { command("previous track", app: app) }

    func seek(to seconds: Double, app: MediaApp?) {
        guard let app = app ?? activeApp() else { return }
        let value = max(0, Int(seconds))
        queue.async {
            _ = self.run("tell application \"\(app.rawValue)\" to set player position to \(value)")
        }
    }

    private func command(_ verb: String, app: MediaApp?) {
        guard let app = app ?? activeApp() else { return }
        queue.async { _ = self.run("tell application \"\(app.rawValue)\" to \(verb)") }
    }

    // MARK: AppleScript runner

    @discardableResult
    private func run(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let output = script.executeAndReturnError(&error)
        if error != nil { return nil }
        return output.stringValue
    }
}
