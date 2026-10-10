import SwiftUI

@MainActor
@main
struct GlassPlayerApp: App {
    @State private var player: PlayerModel
    private let spotify: SpotifySource?

    init() {
        if SpotifyConfig.isConfigured {
            let model = PlayerModel()
            let source = SpotifySource(model: model)
            source.start()
            _player = State(initialValue: model)
            spotify = source
        } else {
            // No Spotify Client ID yet: run the built-in demo track.
            _player = State(initialValue: PlayerModel.demo())
            spotify = nil
        }
    }

    var body: some Scene {
        WindowGroup { NowPlayingView(player: player) }
    }
}
