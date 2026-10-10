import UIKit

/// Reads what's playing from Spotify's Web API and sends play/pause/skip/seek back.
/// Needs Spotify playing on some device (e.g. the Spotify app on this phone), and Premium for the controls.
@MainActor
final class SpotifySource: PlaybackControls {
    private let model: PlayerModel
    private let auth = SpotifyAuth()
    private var pollTask: Task<Void, Never>?
    private var artCache: [String: UIImage] = [:]
    private var backoffUntil = Date.distantPast

    init(model: PlayerModel) {
        self.model = model
        model.controls = self
        model.needsSignIn = !auth.isSignedIn
        model.signIn = { [weak self] in await self?.connect() }
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.poll()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func connect() async {
        do {
            try await auth.signIn()
            model.needsSignIn = false
            await poll()
        } catch {
            model.needsSignIn = !auth.isSignedIn
        }
    }

    // MARK: Polling

    private struct PlayerState: Decodable {
        let is_playing: Bool
        let progress_ms: Int?
        let item: Item?
        struct Item: Decodable {
            let id: String
            let name: String
            let duration_ms: Int
            let artists: [Artist]?
            let album: Album?
        }
        struct Artist: Decodable { let name: String }
        struct Album: Decodable { let name: String; let images: [Image] }
        struct Image: Decodable { let url: String }
    }

    private func poll() async {
        guard auth.isSignedIn else { model.needsSignIn = true; return }
        guard Date() >= backoffUntil else { return }
        guard let (data, status) = await request("GET", "/me/player") else { return }

        if status == 204 {   // no active device
            model.update(track: model.track, position: model.position(at: Date()), isPlaying: false)
            return
        }
        guard status == 200,
              let state = try? JSONDecoder().decode(PlayerState.self, from: data),
              let item = state.item,
              let album = item.album else { return }

        var track = model.track
        if track?.id != item.id {
            let art = await artwork(album.images.first?.url)
            track = Track(id: item.id,
                          title: item.name,
                          artist: (item.artists ?? []).map { $0.name }.joined(separator: ", "),
                          album: album.name,
                          duration: Double(item.duration_ms) / 1000,
                          artwork: art)
        }
        model.update(track: track,
                     position: Double(state.progress_ms ?? 0) / 1000,
                     isPlaying: state.is_playing)
    }

    private func artwork(_ urlString: String?) async -> UIImage? {
        guard let s = urlString, let url = URL(string: s) else { return nil }
        if let hit = artCache[s] { return hit }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let img = UIImage(data: data) else { return nil }
        artCache[s] = img
        return img
    }

    // MARK: Controls (optimistic UI update, then re-sync with Spotify)

    func togglePlay() {
        let wasPlaying = model.isPlaying
        model.update(track: model.track, position: model.position(at: Date()), isPlaying: !wasPlaying)
        Task { await send("PUT", wasPlaying ? "/me/player/pause" : "/me/player/play") }
    }

    func next() { Task { await send("POST", "/me/player/next") } }
    func previous() { Task { await send("POST", "/me/player/previous") } }

    func seek(to seconds: TimeInterval) {
        model.update(track: model.track, position: seconds, isPlaying: model.isPlaying)
        Task { await send("PUT", "/me/player/seek", query: ["position_ms": String(Int(seconds * 1000))]) }
    }

    private func send(_ method: String, _ path: String, query: [String: String] = [:]) async {
        _ = await request(method, path, query: query)
        try? await Task.sleep(for: .milliseconds(500))
        await poll()
    }

    // MARK: HTTP

    private func request(_ method: String, _ path: String, query: [String: String] = [:]) async -> (Data, Int)? {
        do {
            var c = URLComponents(string: "https://api.spotify.com/v1" + path)!
            if !query.isEmpty { c.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
            var req = URLRequest(url: c.url!)
            req.httpMethod = method
            if method != "GET" { req.httpBody = Data() }   // Spotify wants Content-Length: 0 on bodyless PUT/POST
            req.setValue("Bearer \(try await auth.validToken())", forHTTPHeaderField: "Authorization")

            let (data, resp) = try await URLSession.shared.data(for: req)
            let http = resp as? HTTPURLResponse
            if http?.statusCode == 429 {
                let wait = Double(http?.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 10
                backoffUntil = Date().addingTimeInterval(wait)
            }
            return (data, http?.statusCode ?? 0)
        } catch {
            return nil
        }
    }
}
