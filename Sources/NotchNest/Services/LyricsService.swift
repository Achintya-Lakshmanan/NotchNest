import Foundation

/// Lyrics from LRCLIB (lrclib.net), a free, keyless lyrics database. Only the
/// track title, artist, album and duration are sent, and only when the user
/// opens the lyrics view.
enum LyricsService {
    private struct Response: Decodable {
        var instrumental: Bool?
        var plainLyrics: String?
        var syncedLyrics: String?
    }

    static func decode(_ data: Data) -> Lyrics {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { return .unavailable }
        if response.instrumental == true { return .instrumental }
        if let synced = response.syncedLyrics {
            let lines = Lyrics.parseLRC(synced)
            if !lines.isEmpty { return .synced(lines) }
        }
        if let plain = response.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines), !plain.isEmpty {
            return .plain(plain)
        }
        return .unavailable
    }

    struct NetworkError: Error {}

    /// Exact match first; LRCLIB's exact lookup misses when Apple Music album
    /// names differ ("– Single", "(Deluxe)"), so fall back to a search and take
    /// the result whose length is closest to the track's.
    static func fetch(_ np: NowPlaying) async -> Result<Lyrics, NetworkError> {
        var exact = URLComponents(string: "https://lrclib.net/api/get")!
        exact.queryItems = [
            URLQueryItem(name: "track_name", value: np.title),
            URLQueryItem(name: "artist_name", value: np.artist),
            URLQueryItem(name: "album_name", value: np.album),
            URLQueryItem(name: "duration", value: String(Int(np.duration.rounded()))),
        ]
        switch await request(exact.url) {
        case .failure(let error): return .failure(error)
        case .success(let data?):
            let lyrics = decode(data)
            if lyrics != .unavailable { return .success(lyrics) }
        case .success(nil): break      // 404: not found by exact match
        }

        var search = URLComponents(string: "https://lrclib.net/api/search")!
        search.queryItems = [
            URLQueryItem(name: "track_name", value: searchTitle(np.title)),
            URLQueryItem(name: "artist_name", value: np.artist),
        ]
        switch await request(search.url) {
        case .failure(let error): return .failure(error)
        case .success(nil): return .success(.unavailable)
        case .success(let data?): return .success(bestMatch(data, duration: np.duration))
        }
    }

    /// Drops decorations that lyric databases don't use: "(feat. X)",
    /// "[Live]", " - Remastered 2011", " – Radio Edit".
    static func searchTitle(_ title: String) -> String {
        var t = title
        t = t.replacingOccurrences(of: #"\s*[\(\[](feat\.?|ft\.?|with|featuring)\s[^\)\]]*[\)\]]"#,
                                   with: "", options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: #"\s*[\(\[][^\)\]]*(remaster|version|edit|live|mono|stereo|mix|deluxe)[^\)\]]*[\)\]]"#,
                                   with: "", options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: #"\s+[-–—]\s+.*(remaster|version|edit|live|mono|stereo|mix).*$"#,
                                   with: "", options: [.regularExpression, .caseInsensitive])
        let trimmed = t.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? title : trimmed
    }

    /// Picks the closest-length search result (within 5 s) that has lyrics.
    static func bestMatch(_ data: Data, duration: Double) -> Lyrics {
        struct Item: Decodable { var duration: Double?; var instrumental: Bool?; var plainLyrics: String?; var syncedLyrics: String? }
        guard let items = try? JSONDecoder().decode([Item].self, from: data) else { return .unavailable }
        let ranked = items
            .filter { abs(($0.duration ?? .infinity) - duration) <= 5 }
            // A result with nothing in it must not hide a lower-ranked one that has lyrics.
            .filter { $0.instrumental == true
                || !($0.syncedLyrics ?? "").isEmpty
                || !($0.plainLyrics ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { ($0.syncedLyrics != nil ? 0 : 1, abs(($0.duration ?? 0) - duration))
                    < ($1.syncedLyrics != nil ? 0 : 1, abs(($1.duration ?? 0) - duration)) }
        guard let best = ranked.first else { return .unavailable }
        if best.instrumental == true { return .instrumental }
        if let synced = best.syncedLyrics {
            let lines = Lyrics.parseLRC(synced)
            if !lines.isEmpty { return .synced(lines) }
        }
        if let plain = best.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines), !plain.isEmpty {
            return .plain(plain)
        }
        return .unavailable
    }

    /// nil data = 404. Any other failure is a network error.
    private static func request(_ url: URL?) async -> Result<Data?, NetworkError> {
        guard let url else { return .failure(NetworkError()) }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("NotchNest (https://github.com/Achintya-Lakshmanan/NotchNest)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else { return .failure(NetworkError()) }
        if status == 404 { return .success(nil) }
        return status == 200 ? .success(data) : .failure(NetworkError())
    }
}
