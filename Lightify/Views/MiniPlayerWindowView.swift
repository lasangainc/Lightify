//
//  MiniPlayerWindowView.swift
//  Lightify
//

import SwiftUI

/// Shared scene identifier for `Window` / `openWindow`.
enum MiniPlayerWindowScene {
    static let id = "miniPlayer"
}

struct MiniPlayerWindowView: View {
    @Environment(AppSession.self) private var appSession
    @Environment(PlaybackViewModel.self) private var playback
    @State private var skipBackBounceTick = 0
    @State private var skipForwardBounceTick = 0
    @State private var sampledTint: (color: Color, gradientEnd: Color, luminance: CGFloat)?

    private static let symbolReplace = Animation.smooth(duration: 0.23)
    private static let playPauseSymbolReplace = Animation.spring(response: 0.16, dampingFraction: 0.52)
    private static let artworkScaleAnimation = Animation.smooth(duration: 0.26)

    private var useLightForeground: Bool {
        guard let l = sampledTint?.luminance else { return false }
        return l < 0.5
    }

    private var secondaryForeground: Color {
        useLightForeground ? .white.opacity(0.72) : Color(white: 0.38)
    }

    private var controlTint: Color {
        useLightForeground ? .white : Color("AccentColor")
    }

    /// Full size while playing or when idle; slightly smaller when a track is loaded but paused.
    private var artworkDisplayScale: CGFloat {
        guard let np = playback.nowPlaying else { return 1.0 }
        return np.isPlaying ? 1.0 : 0.92
    }

    var body: some View {
        ZStack {
            artworkWindowBackground
                .ignoresSafeArea()

            VStack(spacing: 14) {
                artworkSection
                statusSection

                GlassEffectContainer(spacing: 18) {
                    VStack(spacing: 14) {
                        trackMetadataBubble

                        if let np = playback.nowPlaying, !playback.autoplayBlocked, playback.playerError == nil {
                            PlaybackScrubber(
                                positionMs: np.positionMs,
                                durationMs: np.durationMs,
                                isEnabled: playback.isWebPlayerReady
                            ) { positionMs in
                                playback.seek(to: positionMs)
                            }
                            .padding(.horizontal, 2)
                        }

                        transportBubble

                        volumeBubble
                    }
                }
            }
            .padding(20)
            .padding(.top, 12)
            .frame(minWidth: 300, idealWidth: 320, maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(controlTint)
        .background(alignment: .topLeading) {
            MiniPlayerWindowChrome()
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
        }
        .task(id: playback.nowPlaying?.artworkURL?.absoluteString) {
            await refreshArtworkTint()
        }
    }

    private var artworkWindowBackground: some View {
        Group {
            if let tint = sampledTint {
                LinearGradient(
                    colors: [tint.color, tint.gradientEnd],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
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

    private var artworkSection: some View {
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
                .frame(width: 220, height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
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
                    .foregroundStyle(secondaryForeground)
            }
    }

    /// Title + artist in Liquid Glass for legibility on any artwork-derived background.
    private var trackMetadataBubble: some View {
        VStack(spacing: 4) {
            if let np = playback.nowPlaying {
                Text(np.trackName)
                    .font(.headline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                Text(np.artistName)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Lightify")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("Nothing playing")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: true, vertical: true)
        .padding(.vertical, 12)
        .padding(.horizontal, 22)
        .glassEffect(.regular, in: Capsule())
    }

    @ViewBuilder
    private var statusSection: some View {
        if playback.autoplayBlocked {
            Text("Autoplay blocked — tap play or pick a track")
                .font(.caption)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
        } else if let err = playback.playerError {
            Text(err)
                .font(.caption)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        }
    }

    private var transportBubble: some View {
        HStack(spacing: 22) {
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
                    .contentTransition(.symbolEffect(.replace.offUp.byLayer, options: .nonRepeating))
                    .animation(Self.playPauseSymbolReplace, value: playback.nowPlaying?.isPlaying ?? false)
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
        .foregroundStyle(.primary)
        .padding(.vertical, 10)
        .padding(.horizontal, 18)
        .glassEffect(.regular.interactive(), in: Capsule())
    }

    private var volumeBubble: some View {
        HStack(spacing: 10) {
            Image(systemName: volumeIconName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
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
                .foregroundStyle(.primary)
                .frame(minWidth: 32, alignment: .trailing)
        }
        .padding(.vertical, 10)
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .glassEffect(.regular.interactive(), in: Capsule())
    }

    private var volumeIconName: String {
        let v = playback.playbackVolume
        if v <= 0.001 {
            return "speaker.slash.fill"
        }
        if v < 0.34 {
            return "speaker.wave.1.fill"
        }
        if v < 0.67 {
            return "speaker.wave.2.fill"
        }
        return "speaker.wave.3.fill"
    }
}

#Preview {
    MiniPlayerWindowView()
        .environment(AppSession())
        .environment(PlaybackViewModel())
        .frame(width: 360, height: 480)
}
