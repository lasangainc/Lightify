//
//  NowPlayingControls.swift
//  Lightify
//

import SwiftUI

struct NowPlayingControls: View {
    @Environment(PlaybackViewModel.self) private var playback
    @State private var volumePopoverShown = false
    @State private var queuePopoverShown = false
    @State private var isCollapsed = false
    @State private var skipBackBounceTick = 0
    @State private var skipForwardBounceTick = 0

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
    }

    private var expandedIsland: some View {
        HStack(spacing: 0) {
            transportCluster
                .frame(maxWidth: .infinity, alignment: .leading)

            centerInfo
                .frame(minWidth: 120, maxWidth: 280)

            utilityCluster
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .glassEffect(in: Capsule())
    }

    private var collapsedIsland: some View {
        HStack(spacing: 10) {
            collapsedArtwork
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Button {
                playback.playPause()
            } label: {
                Image(systemName: (playback.nowPlaying?.isPlaying ?? false) ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .islandSymbolReplace(value: playback.nowPlaying?.isPlaying ?? false, animation: Self.islandSymbolReplace)
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
        if let url = playback.nowPlaying?.artworkURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    collapsedArtPlaceholder
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    collapsedArtPlaceholder
                @unknown default:
                    collapsedArtPlaceholder
                }
            }
        } else {
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

    private var transportCluster: some View {
        HStack(spacing: 14) {
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
                        .islandSymbolReplace(value: playback.nowPlaying?.isPlaying ?? false, animation: Self.islandSymbolReplace)
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
        }
    }

    private var centerInfo: some View {
        VStack(spacing: 2) {
            if playback.autoplayBlocked {
                Text("Autoplay blocked — tap play or pick a track")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            } else if let err = playback.playerError {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            } else if let np = playback.nowPlaying {
                VStack(spacing: 2) {
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
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) {
            if let np = playback.nowPlaying, !playback.autoplayBlocked, playback.playerError == nil {
                PlaybackScrubber(
                    positionMs: np.positionMs,
                    durationMs: np.durationMs,
                    isEnabled: playback.isWebPlayerReady
                ) { positionMs in
                    playback.seek(to: positionMs)
                }
                .padding(.horizontal, 4)
                .offset(y: 10)
            }
        }
    }

    private var utilityCluster: some View {
        HStack(spacing: 8) {
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
            } else if let err = playback.queueError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
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

private struct QueueTrackRow: View {
    let track: SpotifyTrack

    var body: some View {
        HStack(spacing: 12) {
            queueThumbnail
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(track.name)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(track.primaryArtistName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var queueThumbnail: some View {
        if let url = track.smallImageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    queuePlaceholder
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    queuePlaceholder
                @unknown default:
                    queuePlaceholder
                }
            }
        } else {
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

private struct PlaybackScrubber: View {
    let positionMs: Int
    let durationMs: Int
    let isEnabled: Bool
    let onSeek: (Int) -> Void

    @State private var dragFraction: Double?

    var body: some View {
        GeometryReader { proxy in
            let progressFraction = displayedFraction

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.14))
                    .frame(height: 3)

                Capsule()
                    .fill(Color("AccentColor").opacity(isEnabled ? 0.9 : 0.35))
                    .frame(width: max(0, proxy.size.width * CGFloat(progressFraction)), height: 3)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard canSeek else { return }
                        dragFraction = fraction(for: value.location.x, width: proxy.size.width)
                    }
                    .onEnded { value in
                        guard canSeek else {
                            dragFraction = nil
                            return
                        }
                        let targetFraction = fraction(for: value.location.x, width: proxy.size.width)
                        dragFraction = nil
                        onSeek(Int((Double(durationMs) * targetFraction).rounded()))
                    }
            )
        }
        .frame(height: 12)
        .help(canSeek ? "Seek" : "Playback progress")
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue(accessibilityValue)
    }

    private var canSeek: Bool {
        isEnabled && durationMs > 0
    }

    private var displayedFraction: Double {
        if let dragFraction {
            return dragFraction
        }
        guard durationMs > 0 else { return 0 }
        return min(max(Double(positionMs) / Double(durationMs), 0), 1)
    }

    private var accessibilityValue: String {
        guard durationMs > 0 else { return "Unavailable" }
        return "\(formattedTime(positionMs)) of \(formattedTime(durationMs))"
    }

    private func fraction(for xPosition: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        let clampedX = min(max(xPosition, 0), width)
        return Double(clampedX / width)
    }

    private func formattedTime(_ milliseconds: Int) -> String {
        let totalSeconds = max(milliseconds / 1000, 0)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    NowPlayingControls()
        .environment(PlaybackViewModel())
        .padding()
        .frame(width: 720)
}
