import AppKit

/// Talks to Apple Music and Spotify via AppleScript. First use will prompt
/// for Automation permission per app (System Settings ▸ Privacy ▸ Automation).
/// Every AppleScript call and all mutable state (the lazily compiled scripts)
/// are confined to `queue`, a serial queue, which is what makes this Sendable.
/// Apple Events can block for seconds, so they deliberately stay off the main thread.
final class MediaController: @unchecked Sendable {
    private let queue = DispatchQueue(label: "notchnest.media", qos: .userInitiated)

    /// Compiled once — compiling NSAppleScript on every 2s poll is wasteful.
    private lazy var spotifyQueryScript = NSAppleScript(source: """
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
        """)
    private lazy var musicQueryScript = NSAppleScript(source: """
        tell application "Music"
          if it is running then
            try
              set t to current track
              set out to (name of t) & "\\n" & (artist of t) & "\\n" & (album of t) & "\\n" & (player state as string) & "\\n" & (player position as string) & "\\n" & (duration of t) & "\\n"
              -- Music calls the heart "favorited" (macOS 14+); older builds used "loved".
              set fav to ""
              try
                set fav to (favorited of t) as string
              on error
                try
                  set fav to (loved of t) as string
                end try
              end try
              return out & "\\n" & fav
            on error
              return ""
            end try
          end if
        end tell
        """)
    private lazy var musicArtworkScript = NSAppleScript(source: """
        tell application "Music"
          if it is running then
            try
              return (data of artwork 1 of current track)
            on error
              return missing value
            end try
          end if
        end tell
        """)

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

    func fetch(completion: @escaping @MainActor @Sendable (NowPlaying?) -> Void) {
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
        let script: NSAppleScript?
        switch app {
        case .spotify: script = spotifyQueryScript
        case .music: script = musicQueryScript
        }
        guard let script, let raw = run(script), !raw.isEmpty else { return nil }
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
            artworkURL: (art?.isEmpty == false) ? art : nil,
            isFavorited: app == .music && parts.count >= 8 ? Self.bool(parts[7]) : nil
        )
    }

    private static func bool(_ value: String) -> Bool? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true": return true
        case "false": return false
        default: return nil
        }
    }

    /// Hearts (favourites) the current Apple Music track.
    func setFavorite(_ favorite: Bool) {
        let value = favorite ? "true" : "false"
        queue.async {
            _ = self.runSource("""
                tell application "Music"
                  try
                    set favorited of current track to \(value)
                  on error
                    try
                      set loved of current track to \(value)
                    end try
                  end try
                end tell
                """)
        }
    }

    // MARK: Apple Music artwork (raw image data)

    func fetchMusicArtwork(completion: @escaping @MainActor @Sendable (NSImage?) -> Void) {
        queue.async {
            var image: NSImage?
            if let script = self.musicArtworkScript {
                var error: NSDictionary?
                let desc = script.executeAndReturnError(&error)
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
            _ = self.runSource("tell application \"\(app.rawValue)\" to set player position to \(value)")
        }
    }

    private func command(_ verb: String, app: MediaApp?) {
        guard let app = app ?? activeApp() else { return }
        queue.async { _ = self.runSource("tell application \"\(app.rawValue)\" to \(verb)") }
    }

    // MARK: AppleScript runner

    @discardableResult
    private func run(_ script: NSAppleScript) -> String? {
        var error: NSDictionary?
        let output = script.executeAndReturnError(&error)
        if error != nil { return nil }
        return output.stringValue
    }

    @discardableResult
    private func runSource(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        return run(script)
    }
}
