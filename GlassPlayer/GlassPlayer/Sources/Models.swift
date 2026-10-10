import SwiftUI
import Observation

struct Track: Identifiable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    var artwork: UIImage?
    /// Demo only: lets the sample track show lyrics without a network call.
    var demoLRC: String?
}

@MainActor
protocol PlaybackControls: AnyObject {
    func togglePlay()
    func next()
    func previous()
    func seek(to seconds: TimeInterval)
}

/// The single object the UI reads. Any source (Spotify, local files, ...) just writes into it.
@MainActor @Observable
final class PlayerModel {
    var track: Track?
    var isPlaying = false
    var controls: PlaybackControls?
    /// Set by a source that needs the user to log in first.
    var needsSignIn = false
    var signIn: (() async -> Void)?

    private var basePosition: TimeInterval = 0
    private var baseDate = Date()

    /// Call whenever the source reports new state (track change, pause, seek, periodic sync).
    func update(track: Track?, position: TimeInterval, isPlaying: Bool) {
        self.track = track
        self.basePosition = position
        self.baseDate = Date()
        self.isPlaying = isPlaying
    }

    /// Smoothly extrapolated position, so lyrics never wait on network polling.
    func position(at date: Date) -> TimeInterval {
        let p = isPlaying ? basePosition + date.timeIntervalSince(baseDate) : basePosition
        return min(max(p, 0), track?.duration ?? p)
    }
}

// MARK: - Demo source so the UI runs with no Spotify at all

@MainActor
final class DemoControls: PlaybackControls {
    unowned let model: PlayerModel
    init(_ model: PlayerModel) { self.model = model }
    func togglePlay() { model.update(track: model.track, position: model.position(at: Date()), isPlaying: !model.isPlaying) }
    func next() { seek(to: 0) }
    func previous() { seek(to: 0) }
    func seek(to s: TimeInterval) { model.update(track: model.track, position: s, isPlaying: model.isPlaying) }
}

extension PlayerModel {
    static func demo() -> PlayerModel {
        let lrc = """
        [00:00.00]
        [00:03.50]City lights are melting into rain
        [00:08.00]Every window glows a different shade
        [00:12.50]I keep the volume low and the night turned up
        [00:17.00]Nothing left to prove, nothing left to say
        [00:21.50]Hold the glow, let it spill on through
        [00:26.00]Everything's a little clearer when it's blue
        [00:30.50]Hold the glow, let it spill on through
        [00:35.00]Everything's a little clearer when it's you
        """
        let size = CGSize(width: 300, height: 300)
        let art = UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [UIColor.systemIndigo.cgColor, UIColor.systemPink.cgColor, UIColor.systemOrange.cgColor] as CFArray
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1])!
            ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
        }
        let m = PlayerModel()
        m.controls = DemoControls(m)
        m.update(track: Track(id: "demo", title: "Hold the Glow", artist: "Demo Artist", album: "Demo",
                              duration: 40, artwork: art, demoLRC: lrc),
                 position: 0, isPlaying: true)
        return m
    }
}
