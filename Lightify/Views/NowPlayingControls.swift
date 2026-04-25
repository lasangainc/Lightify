//
//  NowPlayingControls.swift
//  Lightify
//

import SwiftUI

struct NowPlayingControls: View {
    @Environment(AppSession.self) private var appSession
    @Environment(PlaybackViewModel.self) private var playback
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var volumePopoverShown = false
    @State private var queuePopoverShown = false
    @State private var isCollapsed = false
    @State private var skipBackBounceTick = 0
    @State private var skipForwardBounceTick = 0
    @State private var shuffleBarBounceTick = 0
    @State private var repeatBarBounceTick = 0

    /// Slightly under-damped for a short bounce on collapse/expand.
    private static let islandSpring = Animation.spring(response: 0.42, dampingFraction: 0.62)

    private static let islandSymbolReplace = Animation.smooth(duration: 0.23)

    var body: some View {
        HStack(spacing: 0) {
            if isCollapsed {
                collapsedIsland
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.92, anchor: .leading).combined(with: .opacity),
                        removal: .scale(scale: 0.92, anchor: .leading).combined(with: .opacity)
                    ))
                Spacer(minLength: 0)
            } else {
                expandedIsland
                    .frame(maxWidth: .infinity)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.96, anchor: .bottom).combined(with: .opacity),
                        removal: .scale(scale: 0.96, anchor: .bottom).combined(with: .opacity)
                    ))
            }
        }
        .playbackIssueAlerts()
    }

    private var expandedIsland: some View {
        HStack(spacing: 0) {
            transportCluster
                .frame(maxWidth: .infinity, alignment: .leading)

            centerInfo

            utilityCluster
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .glassEffect(in: Capsule())
    }

    private var collapsedIsland: some View {
        HStack(spacing: 10) {
            Button {
                Task {
                    await appSession.openAlbumFromPlaybackState(
                        contextURI: playback.nowPlaying?.contextURI,
                        trackURI: playback.nowPlaying?.uri,
                        albumNameHint: playback.nowPlaying?.albumName
                    )
                }
            } label: {
                collapsedArtwork
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(playback.nowPlaying == nil)
            .help("Open album")

            Button {
                playback.playPause()
            } label: {
                Image(systemName: (playback.nowPlaying?.isPlaying ?? false) ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .symbolEffect(.bounce, value: playback.nowPlaying?.isPlaying ?? false)
                    .islandPlayPauseSymbolReplace(value: playback.nowPlaying?.isPlaying ?? false)
            }
            .buttonStyle(.plain)
            .help((playback.nowPlaying?.isPlaying ?? false) ? "Pause" : "Play")

            Button {
                withAnimation(Self.islandSpring) {
                    isCollapsed = false
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Expand playback controls")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(in: Capsule())
    }

    @ViewBuilder
    private var collapsedArtwork: some View {
        RemoteArtworkImage(url: playback.nowPlaying?.artworkURL, maxPixelSize: 96) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            collapsedArtPlaceholder
        }
    }

    private var collapsedArtPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.quaternary)
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
            }
    }

    private var expandedBarArtPlaceholder: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(.quaternary)
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
    }

    /// Collapse + mini player. Stroked capsule only—nested `glassEffect` on the main bar reads muddy.
    private var transportLeadingGlassChip: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(Self.islandSpring) {
                    isCollapsed = true
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Minimize playback controls")

            Button {
                volumePopoverShown = false
                queuePopoverShown = false
                playback.dismissMiniPlayerLyricsPanel()
                openWindow(id: MiniPlayerWindowScene.id)
                dismissWindow(id: MainWindowScene.id)
            } label: {
                Image(systemName: "pip.enter")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Open mini player")
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .overlay {
            Capsule()
                .strokeBorder(.secondary.opacity(0.28), lineWidth: 1)
        }
    }

    private var transportCluster: some View {
        HStack(spacing: 14) {
            transportLeadingGlassChip

            Group {
                Button {
                    if !playback.shuffleEnabled {
                        shuffleBarBounceTick &+= 1
                    }
                    playback.setShuffleEnabled(!playback.shuffleEnabled)
                } label: {
                    Image(systemName: "shuffle")
                        .font(.system(size: 14, weight: .semibold))
                        .symbolEffect(.bounce, value: shuffleBarBounceTick)
                }
                .buttonStyle(.plain)
                .foregroundStyle(playback.shuffleEnabled ? Color.green : Color.secondary)
                .disabled(!playback.isWebPlayerReady || playback.nowPlaying == nil)
                .opacity(playback.nowPlaying == nil ? 0.4 : 1)
                .help(playback.shuffleEnabled ? "Shuffle on" : "Shuffle off")

                Group {
                    Button {
                        skipBackBounceTick &+= 1
                        playback.previous()
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .symbolEffect(.bounce, value: skipBackBounceTick)
                    }
                    .buttonStyle(.plain)
                    .help("Previous")

                    Button {
                        playback.playPause()
                    } label: {
                        Image(systemName: (playback.nowPlaying?.isPlaying ?? false) ? "pause.fill" : "play.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .frame(width: 28, height: 28)
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
                            .font(.system(size: 15, weight: .semibold))
                            .symbolEffect(.bounce, value: skipForwardBounceTick)
                    }
                    .buttonStyle(.plain)
                    .help("Next")
                }
                .foregroundStyle(.primary)

                Button {
                    if playback.repeatMode == .off {
                        repeatBarBounceTick &+= 1
                    }
                    playback.cycleRepeatMode()
                } label: {
                    Image(systemName: nowPlayingBarRepeatSymbolName)
                        .font(.system(size: 14, weight: .semibold))
                        .symbolEffect(.bounce, value: repeatBarBounceTick)
                        .contentTransition(.symbolEffect(.replace.magic(fallback: .downUp.byLayer), options: .nonRepeating))
                        .animation(Self.islandSymbolReplace, value: nowPlayingBarRepeatSymbolName)
                }
                .buttonStyle(.plain)
                .foregroundStyle(nowPlayingBarRepeatForeground)
                .disabled(!playback.isWebPlayerReady || playback.nowPlaying == nil)
                .opacity(playback.nowPlaying == nil ? 0.4 : 1)
                .help(PlaybackTransportFormatting.repeatHelp(for: playback.repeatMode))
            }
        }
    }

    private var nowPlayingBarRepeatSymbolName: String {
        PlaybackTransportFormatting.repeatSymbolName(for: playback.repeatMode)
    }

    private var nowPlayingBarRepeatForeground: Color {
        switch playback.repeatMode {
        case .off:
            .secondary
        case .context, .track:
            .green
        }
    }

    private var centerInfo: some View {
        HStack(alignment: .center, spacing: 8) {
            expandedBarArtwork

            VStack(alignment: .leading, spacing: 2) {
                if let np = playback.nowPlaying {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(np.trackName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(np.artistName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    Text("Lightify")
                        .font(.subheadline.weight(.semibold))
                    Text("Nothing playing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 160, maxWidth: 300)
        .overlay(alignment: .bottomLeading) {
            if let np = playback.nowPlaying, !playback.autoplayBlocked {
                PlaybackScrubber(
                    positionMs: np.positionMs,
                    durationMs: np.durationMs,
                    isEnabled: playback.isWebPlayerReady
                ) { positionMs in
                    playback.seek(to: positionMs)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .offset(y: 10)
            }
        }
    }

    /// Album art for the expanded bar (collapsed state already shows a thumbnail).
    private var expandedBarArtwork: some View {
        Button {
            Task {
                await appSession.openAlbumFromPlaybackState(
                    contextURI: playback.nowPlaying?.contextURI,
                    trackURI: playback.nowPlaying?.uri,
                    albumNameHint: playback.nowPlaying?.albumName
                )
            }
        } label: {
            RemoteArtworkImage(url: playback.nowPlaying?.artworkURL, maxPixelSize: 80) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                expandedBarArtPlaceholder
            }
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(playback.nowPlaying == nil)
        .help("Open album")
    }

    private var utilityCluster: some View {
        HStack(spacing: 8) {
            Button {
                volumePopoverShown = false
                queuePopoverShown = false
                guard playback.nowPlaying != nil else { return }
                playback.presentMiniPlayerWithLyricsPanel()
                openWindow(id: MiniPlayerWindowScene.id)
                dismissWindow(id: MainWindowScene.id)
            } label: {
                Image(systemName: "quote.bubble")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(playback.nowPlaying == nil)
            .opacity(playback.nowPlaying == nil ? 0.4 : 1)
            .help("Lyrics")

            Button {
                volumePopoverShown = false
                queuePopoverShown.toggle()
            } label: {
                Image(systemName: "music.note.list")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(!playback.isWebPlayerReady)
            .help("Queue")
            .popover(isPresented: $queuePopoverShown, arrowEdge: .bottom) {
                queuePopoverContent
                    .padding(12)
                    .frame(minWidth: 380, idealWidth: 440, maxWidth: 560, minHeight: 280, idealHeight: 480, maxHeight: 640)
            }

            Button {
                queuePopoverShown = false
                volumePopoverShown.toggle()
            } label: {
                Image(systemName: volumeIconName)
                    .font(.system(size: 14, weight: .medium))
                    .islandSymbolReplace(value: volumeIconName, animation: Self.islandSymbolReplace)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(!playback.isWebPlayerReady)
            .help("Volume")
            .popover(isPresented: $volumePopoverShown, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Slider(
                        value: Binding(
                            get: { playback.playbackVolume },
                            set: { playback.setPlaybackVolume($0) }
                        ),
                        in: 0 ... 1
                    )
                    Text("\(Int(round(playback.playbackVolume * 100)))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(12)
                .frame(width: 200)
            }
        }
        .onChange(of: queuePopoverShown) { _, isShown in
            guard isShown else { return }
            Task { await playback.refreshPlaybackQueue() }
        }
    }

    @ViewBuilder
    private var queuePopoverContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if playback.isLoadingQueue {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else if playback.queueError != nil {
                Text("Couldn’t load the queue.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 4)
            } else if playback.playbackQueue.isEmpty {
                Text("Nothing queued up next")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 4)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(playback.playbackQueue) { track in
                            QueueTrackRow(track: track)
                        }
                    }
                }
                .frame(maxHeight: 560)
            }
        }
    }

    private var volumeIconName: String {
        PlaybackTransportFormatting.volumeSpeakerSymbolName(playbackVolume: playback.playbackVolume)
    }
}

private struct QueueTrackRow: View {
    let track: SpotifyTrack
    @Environment(PlaybackViewModel.self) private var playback

    private var playDisabled: Bool { !playback.isWebPlayerReady }

    var body: some View {
        Button {
            playback.playTrack(id: track.id)
        } label: {
            HStack(spacing: 12) {
                queueThumbnail
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(track.name)
                        .font(.body.weight(.medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.primary)
                    Text(track.primaryArtistName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(playDisabled)
        .opacity(playDisabled ? 0.45 : 1)
        .accessibilityLabel("Play \(track.name) by \(track.primaryArtistName)")
    }

    @ViewBuilder
    private var queueThumbnail: some View {
        RemoteArtworkImage(url: track.smallImageURL, maxPixelSize: 96) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            queuePlaceholder
        }
    }

    private var queuePlaceholder: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(.quaternary)
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
            }
    }
}

private extension View {
    func islandSymbolReplace<V: Equatable>(value: V, animation: Animation) -> some View {
        self
            .contentTransition(.symbolEffect(.replace))
            .animation(animation, value: value)
    }
}

#Preview {
    NowPlayingControls()
        .environment(AppSession())
        .environment(PlaybackViewModel())
        .padding()
        .frame(width: 720)
}
