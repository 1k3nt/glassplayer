import SwiftUI

// Targets iOS 26 (glassEffect / MeshGradient). Haptics need a real iPhone, not the simulator.

struct NowPlayingView: View {
    let player: PlayerModel
    @State private var lyrics: [LyricLine] = []
    @State private var showLyrics = true
    @AppStorage("hapticsOn") private var hapticsOn = true

    var body: some View {
        ZStack {
            FluidBackground(colors: palette)
            VStack(spacing: 20) {
                header
                if player.needsSignIn {
                    signInPane
                } else if player.track == nil {
                    emptyPane
                } else if showLyrics {
                    lyricsPane
                } else {
                    artwork.padding(.horizontal, 24)
                }
                Spacer(minLength: 0)
                controls
                attribution
            }
            .padding()
        }
        .preferredColorScheme(.dark)
        .task(id: player.track?.id) {
            guard let track = player.track else { lyrics = []; return }
            if let demo = track.demoLRC { lyrics = LRCParser.parse(demo); return }
            lyrics = []
            lyrics = await LyricsService.shared.lyrics(title: track.title, artist: track.artist,
                                                       album: track.album, duration: track.duration,
                                                       key: track.id)
        }
    }

    private var palette: [Color] {
        if let img = player.track?.artwork { return ArtworkPalette.grid(from: img) }
        return ArtworkPalette.fallback
    }

    private var header: some View {
        HStack(spacing: 12) {
            if showLyrics, let img = player.track?.artwork {
                Image(uiImage: img).resizable().scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(.rect(cornerRadius: 10))
            }
            VStack(alignment: .leading) {
                Text(player.track?.title ?? "GlassPlayer").font(.headline).lineLimit(1)
                Text(player.track?.artist ?? "").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button { hapticsOn.toggle() } label: {
                Image(systemName: hapticsOn ? "iphone.radiowaves.left.and.right" : "iphone.slash")
            }
            .buttonStyle(.glass)
        }
    }

    private var signInPane: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("Connect your Spotify account to see what's playing.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Connect Spotify") { Task { await player.signIn?() } }
                .buttonStyle(.glassProminent).controlSize(.large)
            Spacer()
        }
    }

    private var emptyPane: some View {
        VStack {
            Spacer()
            Text("Start playing something in the Spotify app.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var lyricsPane: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15)) { ctx in
            let pos = player.position(at: ctx.date)
            let active = lyrics.lastIndex(where: { $0.time <= pos }) ?? -1
            LyricsView(lines: lyrics, active: active, hapticsOn: hapticsOn) { player.controls?.seek(to: $0) }
        }
    }

    /// "Live cover": artwork breathes with play/pause while the background flows in its colors.
    private var artwork: some View {
        Group {
            if let img = player.track?.artwork {
                Image(uiImage: img).resizable().scaledToFit()
            } else {
                Color.gray.aspectRatio(1, contentMode: .fit)
            }
        }
        .clipShape(.rect(cornerRadius: 24))
        .shadow(color: .black.opacity(0.4), radius: 30, y: 20)
        .scaleEffect(player.isPlaying ? 1 : 0.85)
        .animation(.spring(duration: 0.5, bounce: 0.3), value: player.isPlaying)
    }

    private var controls: some View {
        GlassEffectContainer(spacing: 24) {
            HStack(spacing: 24) {
                Button { player.controls?.previous() } label: { Image(systemName: "backward.fill") }
                Button { player.controls?.togglePlay() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title)
                }
                Button { player.controls?.next() } label: { Image(systemName: "forward.fill") }
                Button { showLyrics.toggle() } label: { Image(systemName: showLyrics ? "photo" : "quote.bubble") }
            }
            .buttonStyle(.glass)
            .controlSize(.large)
        }
        .sensoryFeedback(trigger: player.isPlaying) { _, _ in
            hapticsOn ? SensoryFeedback.impact(weight: .light) : nil
        }
    }

    /// Spotify's developer rules ask apps to credit Spotify and link back to the content.
    @ViewBuilder private var attribution: some View {
        if let id = player.track?.id, id != "demo", let url = URL(string: "https://open.spotify.com/track/\(id)") {
            Link("Open in Spotify", destination: url)
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Lyrics

struct LyricsView: View {
    let lines: [LyricLine]
    let active: Int
    let hapticsOn: Bool
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(lines) { line in
                        let isActive = line.id == active
                        Text(line.text.isEmpty ? "♪" : line.text)
                            .font(.system(size: 30, weight: .bold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .opacity(isActive ? 1 : 0.4)
                            .blur(radius: isActive ? 0 : 1.2)
                            .scaleEffect(isActive ? 1 : 0.95, anchor: .leading)
                            .animation(.smooth(duration: 0.4), value: isActive)
                            .onTapGesture { onSeek(line.time) }
                            .id(line.id)
                    }
                    if lines.isEmpty {
                        Text("No synced lyrics for this track.")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 200)
            }
            .onChange(of: active) { _, new in
                withAnimation(.smooth(duration: 0.6)) { proxy.scrollTo(new, anchor: .center) }
            }
            // Haptic tick each time the highlighted lyric line changes.
            .sensoryFeedback(trigger: active) { _, new in
                (hapticsOn && new >= 0) ? SensoryFeedback.selection : nil
            }
        }
        .mask(LinearGradient(stops: [
            Gradient.Stop(color: .clear, location: 0),
            Gradient.Stop(color: .black, location: 0.12),
            Gradient.Stop(color: .black, location: 0.88),
            Gradient.Stop(color: .clear, location: 1),
        ], startPoint: .top, endPoint: .bottom))
    }
}

// MARK: - Background

struct FluidBackground: View {
    let colors: [Color]   // must contain 9 colors

    var body: some View {
        TimelineView(.animation) { ctx in
            MeshGradient(width: 3, height: 3,
                         points: Self.points(Float(ctx.date.timeIntervalSinceReferenceDate)),
                         colors: colors)
                .overlay(Color.black.opacity(0.3))
        }
        .ignoresSafeArea()
    }

    static func points(_ t: Float) -> [SIMD2<Float>] {
        let a: Float = 0.5 + 0.08 * sin(t * 0.7)
        let b: Float = 0.5 + 0.12 * sin(t * 0.5)
        let c: Float = 0.5 + 0.12 * cos(t * 0.6)
        let d: Float = 0.5 + 0.08 * cos(t * 0.8)
        return [
            SIMD2<Float>(0, 0), SIMD2<Float>(0.5, 0), SIMD2<Float>(1, 0),
            SIMD2<Float>(0, a), SIMD2<Float>(b, c), SIMD2<Float>(1, d),
            SIMD2<Float>(0, 1), SIMD2<Float>(0.5, 1), SIMD2<Float>(1, 1),
        ]
    }
}

enum ArtworkPalette {
    static let fallback: [Color] = Array(repeating: Color(white: 0.15), count: 9)

    /// Shrinks the artwork to 3x3 pixels; each pixel becomes one mesh-gradient control color.
    static func grid(from image: UIImage) -> [Color] {
        guard let cg = image.cgImage else { return fallback }
        var px = [UInt8](repeating: 0, count: 3 * 3 * 4)
        let ok: Bool = px.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: 3, height: 3, bitsPerComponent: 8,
                                      bytesPerRow: 12, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 3, height: 3))
            return true
        }
        guard ok else { return fallback }
        return (0..<9).map { i in
            Color(.sRGB, red: Double(px[i * 4]) / 255, green: Double(px[i * 4 + 1]) / 255,
                  blue: Double(px[i * 4 + 2]) / 255, opacity: 1)
        }
    }
}
