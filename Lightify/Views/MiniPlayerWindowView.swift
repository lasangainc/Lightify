//
//  MiniPlayerWindowView.swift
//  Lightify
//

import SwiftUI

/// Content sizes for the non-resizable mini player (see `Window` + `MiniPlayerWindowChrome`).
enum MiniPlayerWindowMetrics {
    static let compact = CGSize(width: 380, height: 540)
    static let withLyrics = CGSize(width: 980, height: 520)
}

/// Shared scene identifier for `WindowGroup` / `dismissWindow`.
enum MainWindowScene {
    static let id = "main"
}

/// Shared scene identifier for `Window` / `openWindow`.
enum MiniPlayerWindowScene {
    static let id = "miniPlayer"
}

struct MiniPlayerWindowView: View {
    @Environment(AppSession.self) private var appSession
    @Environment(PlaybackViewModel.self) private var playback
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var skipBackBounceTick = 0
    @State private var skipForwardBounceTick = 0
    @State private var shuffleBounceTick = 0
    @State private var repeatBounceTick = 0
    @State private var lyricsBounceTick = 0
    @State private var sampledTint: (color: Color, gradientEnd: Color, luminance: CGFloat)?

    private static let symbolReplace = Animation.smooth(duration: 0.23)
    private static let artworkScaleAnimation = Animation.smooth(duration: 0.26)

    /// Filled / stroked control capsules: solid surfaces, no material glass. Biased so only
    /// clearly high-luminance artwork flips to dark chrome—avoids the bad light-on-light case in the mid band.
    private var miniControlChrome: MiniPlayerControlChrome {
        MiniPlayerControlChrome.from(luminance: sampledTint?.luminance)
    }

    private var controlTint: Color {
        miniControlChrome.sliderTint
    }

    /// Perceived light wash in `artworkWindowBackground` (kept independent of the control flip band).
    private var radialWhiteOpacity: Double {
        guard let l = sampledTint?.luminance else { return 0.18 }
        return l < 0.5 ? 0.08 : 0.18
    }

    private var lyricsForeground: Color {
        .white
    }

    /// Full size while playing or when idle; slightly smaller when a track is loaded but paused.
    private var artworkDisplayScale: CGFloat {
        guard let np = playback.nowPlaying else { return 1.0 }
        return np.isPlaying ? 1.0 : 0.92
    }

    var body: some View {
        let contentSize = playback.miniPlayerShowsLyricsPanel ? MiniPlayerWindowMetrics.withLyrics : MiniPlayerWindowMetrics.compact
        return ZStack {
            artworkWindowBackground
                .ignoresSafeArea()

            if playback.miniPlayerShowsLyricsPanel {
                expandedPlayerWithLyricsLayout
            } else {
                compactPlayerLayout
            }
        }
        .frame(width: contentSize.width, height: contentSize.height)
        .animation(.smooth(duration: 0.32), value: playback.miniPlayerShowsLyricsPanel)
        .tint(controlTint)
        .background(alignment: .topLeading) {
            MiniPlayerWindowChrome()
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
        }
        .task(id: playback.nowPlaying?.artworkURL?.absoluteString) {
            await refreshArtworkTint()
        }
        .playbackIssueAlerts()
    }

    /// Default narrow mini player (PIP-style); centered when the window is wider than the column.
    private var compactPlayerLayout: some View {
        HStack {
            Spacer(minLength: 0)
            VStack(spacing: 14) {
                artworkSection(side: 220)

                VStack(spacing: 18) {
                    playerChromeStack(spacing: 14)
                }
            }
            .padding(20)
            .frame(minWidth: 300, idealWidth: 320, maxWidth: 380, maxHeight: .infinity, alignment: .center)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Wide layout: controls + artwork on the left, fetched lyrics (line-by-line) on the right.
    private var expandedPlayerWithLyricsLayout: some View {
        HStack(alignment: .center, spacing: 44) {
            VStack(spacing: 14) {
                artworkSection(side: 172)

                VStack(spacing: 14) {
                    playerChromeStack(spacing: 12)
                }
            }
            .frame(width: 356)
            .frame(maxHeight: .infinity, alignment: .center)
            .padding(.leading, 28)
            .padding(.vertical, 22)

            lyricsColumn
        }
        .padding(.trailing, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var lyricsColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let np = playback.nowPlaying {
                MiniPlayerLyricsPanel(
                    trackName: np.trackName,
                    artistName: np.artistName
                )
            } else {
                Text("Nothing playing")
                    .font(.body)
                    .foregroundStyle(lyricsForeground.opacity(0.72))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func playerChromeStack(spacing: CGFloat) -> some View {
        VStack(spacing: spacing) {
            trackMetadataBubble

            if let np = playback.nowPlaying, !playback.autoplayBlocked {
                PlaybackScrubber(
                    positionMs: np.positionMs,
                    durationMs: np.durationMs,
                    isEnabled: playback.isWebPlayerReady,
                    trackColor: miniControlChrome.scrubberTrack,
                    progressColor: miniControlChrome.scrubberProgress
                ) { positionMs in
                    playback.seek(to: positionMs)
                }
                .padding(.horizontal, 2)
            }

            transportBubble

            volumeBubble
        }
    }

    private var artworkWindowBackground: some View {
        ZStack {
            if let tint = sampledTint {
                LinearGradient(
                    colors: [
                        tint.gradientEnd.opacity(0.96),
                        tint.color.opacity(0.94),
                        tint.gradientEnd.opacity(0.98)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    RadialGradient(
                        colors: [
                            .white.opacity(radialWhiteOpacity),
                            .clear
                        ],
                        center: .center,
                        startRadius: 30,
                        endRadius: 420
                    )
                }
                .overlay(alignment: .trailing) {
                    LinearGradient(
                        colors: [
                            .clear,
                            .black.opacity(0.1),
                            .black.opacity(0.22)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
            } else {
                Color(nsColor: .underPageBackgroundColor)
            }
        }
    }

    @MainActor
    private func refreshArtworkTint() async {
        sampledTint = nil
        guard let url = playback.nowPlaying?.artworkURL else { return }
        do {
            let image = try await ArtworkPipeline.shared.image(for: url, maxPixelSize: 96)
            sampledTint = ArtworkColorSampler.tint(from: image)
        } catch {
            sampledTint = nil
        }
    }

    private func artworkSection(side: CGFloat) -> some View {
        Button {
            Task {
                await appSession.openAlbumFromPlaybackState(
                    contextURI: playback.nowPlaying?.contextURI,
                    trackURI: playback.nowPlaying?.uri,
                    albumNameHint: playback.nowPlaying?.albumName
                )
            }
        } label: {
            artworkImage
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: side > 200 ? 16 : 12, y: side > 200 ? 8 : 6)
                .scaleEffect(artworkDisplayScale)
                .animation(Self.artworkScaleAnimation, value: artworkDisplayScale)
        }
        .buttonStyle(.plain)
        .disabled(playback.nowPlaying == nil)
        .help("Open album")
    }

    @ViewBuilder
    private var artworkImage: some View {
        RemoteArtworkImage(url: playback.nowPlaying?.artworkURL, maxPixelSize: 440) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            artworkPlaceholder
        }
    }

    private var artworkPlaceholder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.quaternary)
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(miniControlChrome.primary.opacity(0.5))
            }
    }

    /// Title + artist; colors follow `miniControlChrome` (no pill background).
    private var trackMetadataBubble: some View {
        VStack(spacing: 4) {
            if let np = playback.nowPlaying {
                Text(np.trackName)
                    .font(.headline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .foregroundStyle(miniControlChrome.primary)
                Text(np.artistName)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .foregroundStyle(miniControlChrome.secondary)
            } else {
                Text("Lightify")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(miniControlChrome.primary)
                Text("Nothing playing")
                    .font(.subheadline)
                    .foregroundStyle(miniControlChrome.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: true, vertical: true)
        .padding(.vertical, 8)
        .padding(.horizontal, 18)
    }

    private var transportBubble: some View {
        HStack(spacing: 14) {
            Button {
                if !playback.shuffleEnabled {
                    shuffleBounceTick &+= 1
                }
                playback.setShuffleEnabled(!playback.shuffleEnabled)
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 16, weight: .semibold))
                    .symbolEffect(.bounce, value: shuffleBounceTick)
            }
            .buttonStyle(.plain)
            .foregroundStyle(shuffleControlForeground)
            .disabled(!playback.isWebPlayerReady || playback.nowPlaying == nil)
            .opacity(playback.nowPlaying == nil ? 0.4 : 1)
            .help(playback.shuffleEnabled ? "Shuffle on" : "Shuffle off")

            Group {
                Button {
                    skipBackBounceTick &+= 1
                    playback.previous()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .symbolEffect(.bounce, value: skipBackBounceTick)
                }
                .buttonStyle(.plain)
                .help("Previous")

                Button {
                    playback.playPause()
                } label: {
                    Image(systemName: (playback.nowPlaying?.isPlaying ?? false) ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .symbolEffect(.bounce, value: playback.nowPlaying?.isPlaying ?? false)
                        .islandPlayPauseSymbolReplace(value: playback.nowPlaying?.isPlaying ?? false)
                }
                .buttonStyle(.plain)
                .help((playback.nowPlaying?.isPlaying ?? false) ? "Pause" : "Play")

                Button {
                    skipForwardBounceTick &+= 1
                    playback.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .symbolEffect(.bounce, value: skipForwardBounceTick)
                }
                .buttonStyle(.plain)
                .help("Next")
            }
            .foregroundStyle(miniControlChrome.primary)

            Button {
                if playback.repeatMode == .off {
                    repeatBounceTick &+= 1
                }
                playback.cycleRepeatMode()
            } label: {
                Image(systemName: repeatModeSymbolName)
                    .font(.system(size: 16, weight: .semibold))
                    .symbolEffect(.bounce, value: repeatBounceTick)
                    .contentTransition(.symbolEffect(.replace.magic(fallback: .downUp.byLayer), options: .nonRepeating))
                    .animation(Self.symbolReplace, value: repeatModeSymbolName)
            }
            .buttonStyle(.plain)
            .foregroundStyle(repeatControlForeground)
            .disabled(!playback.isWebPlayerReady || playback.nowPlaying == nil)
            .opacity(playback.nowPlaying == nil ? 0.4 : 1)
            .help(PlaybackTransportFormatting.repeatHelp(for: playback.repeatMode))
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
    }

    private var shuffleControlForeground: Color {
        if playback.shuffleEnabled { return .green }
        return miniControlChrome.primary
    }

    private var repeatModeSymbolName: String {
        PlaybackTransportFormatting.repeatSymbolName(for: playback.repeatMode)
    }

    private var repeatControlForeground: Color {
        switch playback.repeatMode {
        case .off:
            return miniControlChrome.primary
        case .context, .track:
            return .green
        }
    }

    private var volumeBubble: some View {
        HStack(spacing: 10) {
            Image(systemName: volumeIconName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(miniControlChrome.primary)
                .frame(width: 22, alignment: .center)
                .contentTransition(.symbolEffect(.replace))
                .animation(Self.symbolReplace, value: volumeIconName)

            Slider(
                value: Binding(
                    get: { playback.playbackVolume },
                    set: { playback.setPlaybackVolume($0) }
                ),
                in: 0 ... 1
            )
            .frame(width: 168)
            .disabled(!playback.isWebPlayerReady)

            Text("\(Int(round(playback.playbackVolume * 100)))%")
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(miniControlChrome.primary)
                .frame(minWidth: 32, alignment: .trailing)

            Button {
                guard playback.nowPlaying != nil else { return }
                lyricsBounceTick &+= 1
                if playback.miniPlayerShowsLyricsPanel {
                    playback.dismissMiniPlayerLyricsPanel()
                } else {
                    playback.presentMiniPlayerWithLyricsPanel()
                }
            } label: {
                Image(systemName: playback.miniPlayerShowsLyricsPanel ? "quote.bubble.fill" : "quote.bubble")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(miniControlChrome.primary)
                    .frame(width: 22, alignment: .center)
                    .symbolEffect(.bounce.down.byLayer, options: .nonRepeating, value: lyricsBounceTick)
            }
            .buttonStyle(.plain)
            .disabled(playback.nowPlaying == nil)
            .opacity(playback.nowPlaying == nil ? 0.4 : 1)
            .help(playback.miniPlayerShowsLyricsPanel ? "Hide lyrics" : "Show lyrics")

            Button {
                openWindow(id: MainWindowScene.id)
                dismissWindow(id: MiniPlayerWindowScene.id)
            } label: {
                Image(systemName: "pip.exit")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(miniControlChrome.primary)
                    .frame(width: 22, alignment: .center)
            }
            .buttonStyle(.plain)
            .help("Return to main window")
        }
        .padding(.vertical, 6)
        .padding(.leading, 8)
        .padding(.trailing, 10)
    }

    private var volumeIconName: String {
        PlaybackTransportFormatting.volumeSpeakerSymbolName(playbackVolume: playback.playbackVolume)
    }
}

// MARK: - Control chrome (pop-out player only; Genius attribution in lyrics keeps system glass)

/// Control chrome: light-on-dark for almost all artwork; dark-on-light only when the sampled average is
/// near-white (very high luminance), plus when there is no sample (window background reads light).
private struct MiniPlayerControlChrome {
    let primary: Color
    let secondary: Color
    let scrubberTrack: Color
    let scrubberProgress: Color
    let sliderTint: Color

    static func from(luminance: CGFloat?) -> MiniPlayerControlChrome {
        // No artwork tint: underPage-style background is usually light → dark chrome reads better.
        guard let l = luminance else { return .darkOnLight }
        // Only flip to dark chrome when the art average is clearly near-white (not mid pastels).
        if l > 0.90 { return .darkOnLight }
        return .lightOnDark
    }

    /// For dark, saturated artwork: light text/icons.
    private static let lightOnDark = MiniPlayerControlChrome(
        primary: .white,
        secondary: .white.opacity(0.7),
        scrubberTrack: .white.opacity(0.22),
        scrubberProgress: Color("AccentColor"),
        sliderTint: .white
    )

    /// For near-white art: dark labels and scrubber track for contrast on the gradient.
    private static let darkOnLight = MiniPlayerControlChrome(
        primary: Color(white: 0.1),
        secondary: Color(white: 0.4),
        scrubberTrack: Color(white: 0.0).opacity(0.2),
        scrubberProgress: Color("AccentColor"),
        sliderTint: Color("AccentColor")
    )
}

#Preview {
    MiniPlayerWindowView()
        .environment(AppSession())
        .environment(PlaybackViewModel())
        .frame(width: MiniPlayerWindowMetrics.compact.width, height: MiniPlayerWindowMetrics.compact.height)
}
