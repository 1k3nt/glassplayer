import Foundation

struct LyricLine: Identifiable, Equatable {
    let id: Int          // index in the sorted list
    let time: TimeInterval
    let text: String
}

enum LRCParser {
    /// Parses standard LRC ("[mm:ss.xx] text"), including lines with several timestamps.
    static func parse(_ lrc: String) -> [LyricLine] {
        let stamp = try! NSRegularExpression(pattern: #"\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]"#)
        var raw: [(time: TimeInterval, text: String)] = []

        for lineSub in lrc.split(whereSeparator: \.isNewline) {
            let line = String(lineSub)
            let ns = line as NSString
            let matches = stamp.matches(in: line, range: NSRange(location: 0, length: ns.length))
            guard let last = matches.last else { continue }
            let text = ns.substring(from: NSMaxRange(last.range)).trimmingCharacters(in: .whitespaces)

            for m in matches {
                let minutes = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let seconds = Double(ns.substring(with: m.range(at: 2))) ?? 0
                var fraction = 0.0
                if m.range(at: 3).location != NSNotFound {
                    let f = ns.substring(with: m.range(at: 3))
                    fraction = (Double(f) ?? 0) / pow(10, Double(f.count))
                }
                raw.append((minutes * 60 + seconds + fraction, text))
            }
        }
        let sorted = raw.sorted { $0.time < $1.time }
        var out: [LyricLine] = []
        for (i, item) in sorted.enumerated() {
            out.append(LyricLine(id: i, time: item.time, text: item.text))
        }
        return out
    }
}

/// Fetches time-synced lyrics from LRCLIB (community database, no API key).
/// Spotify has no public lyrics API. For a commercial release, use a licensed provider instead.
actor LyricsService {
    static let shared = LyricsService()
    private var cache: [String: [LyricLine]] = [:]
    private struct Response: Decodable { let syncedLyrics: String? }

    func lyrics(title: String, artist: String, album: String, duration: TimeInterval, key: String) async -> [LyricLine] {
        if let hit = cache[key] { return hit }

        var c = URLComponents(string: "https://lrclib.net/api/get")!
        c.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "album_name", value: album),
            URLQueryItem(name: "duration", value: String(Int(duration.rounded()))),
        ]
        var request = URLRequest(url: c.url!)
        request.setValue("GlassPlayer/0.1 (your-contact@example.com)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                if status == 404 { cache[key] = [] }
                return []
            }
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            let lines = LRCParser.parse(decoded.syncedLyrics ?? "")
            cache[key] = lines
            return lines
        } catch {
            return []
        }
    }
}
