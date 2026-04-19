//
//  TrackRow.swift
//  Lightify
//

import SwiftUI

struct TrackAddToPlaylistButton: View {
    let track: SpotifyTrack
    @Environment(AppSession.self) private var appSession
    @State private var showsCheckmark = false
    @State private var isPickerOpen = false

    var body: some View {
        Button {
            isPickerOpen = true
        } label: {
            Image(systemName: showsCheckmark ? "checkmark" : "plus")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentTransition(
                    .symbolEffect(.replace.magic(fallback: .downUp.byLayer), options: .nonRepeating)
                )
        }
        .buttonStyle(.plain)
        .help("Add to playlist")
        .accessibilityLabel(showsCheckmark ? "Added to playlist" : "Add to playlist")
        .popover(isPresented: $isPickerOpen, arrowEdge: .bottom) {
            AddToPlaylistPicker(
                track: track,
                onSelect: { playlistID in
                    isPickerOpen = false
                    addTrack(to: playlistID)
                },
                onCreateNew: {
                    isPickerOpen = false
                    appSession.presentNewPlaylistSheet(trackToAddFirst: track)
                }
            )
        }
    }

    private func addTrack(to playlistID: String) {
        Task { @MainActor in
            do {
                try await appSession.addTrackToPlaylist(trackID: track.id, playlistID: playlistID)
                await Task.yield()
                withAnimation {
                    showsCheckmark = true
                }
            } catch {
            }
        }
    }
}

private struct AddToPlaylistPicker: View {
    let track: SpotifyTrack
    let onSelect: (String) -> Void
    let onCreateNew: () -> Void

    @Environment(AppSession.self) private var appSession

    var body: some View {
        VStack(alignment: .leading) {
            if appSession.modifiablePlaylists.isEmpty {
                Text("No editable playlists")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(appSession.modifiablePlaylists) { playlist in
                    Button(playlist.name) {
                        onSelect(playlist.id)
                    }
                    .disabled(appSession.isAddingTrack(track.id, toPlaylist: playlist.id))
                }

                Divider()
            }

            Button {
                onCreateNew()
            } label: {
                Label("New Playlist…", systemImage: "plus.square.on.square")
            }
        }
        .padding()
    }
}

struct TrackHeartButton: View {
    let track: SpotifyTrack
    @Environment(AppSession.self) private var appSession

    var body: some View {
        let liked = appSession.isTrackLiked(track.id)
        let busy = appSession.isTogglingLikedTrack(track.id)
        Button {
            Task { await appSession.toggleLikedStatus(for: track) }
        } label: {
            Image(systemName: liked ? "heart.fill" : "heart")
                .font(.body)
                .foregroundStyle(liked ? Color("AccentColor") : .secondary)
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .opacity(busy ? 0.45 : 1)
        .help(liked ? "Remove from Liked Songs" : "Save to Liked Songs")
    }
}

/// Row for a track with play; optional tap on artist line when the track has a single credited artist with id.
struct TrackRow: View {
    let track: SpotifyTrack
    var onPlay: () -> Void
    var playDisabled: Bool = false
    var onArtistTap: (() -> Void)? = nil
    /// When set, tapping the artwork opens the album instead of playing (title/play button still play).
    var onAlbumArtTap: (() -> Void)? = nil

    @Environment(PlaybackViewModel.self) private var playback

    private static let listPlayIconAnimation = Animation.spring(response: 0.16, dampingFraction: 0.52)

    private var listPlayButtonShowsPause: Bool {
        playback.isActivePlayingTrack(id: track.id)
    }

    /// Same semantics as the main play/pause control: toggle when this track is already current, otherwise start it.
    private func playOrTogglePlayback() {
        if playback.isNowPlayingTrack(id: track.id) {
            playback.playPause()
        } else {
            onPlay()
        }
    }

    private var playControlAccessibilityLabel: String {
        if playback.isNowPlayingTrack(id: track.id) {
            return (playback.nowPlaying?.isPlaying ?? false) ? "Pause" : "Play"
        }
        return "Play \(track.name) by \(track.primaryArtistName)"
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                if let onAlbumArtTap {
                    onAlbumArtTap()
                } else {
                    playOrTogglePlayback()
                }
            } label: {
                trackThumbnail
            }
            .buttonStyle(.plain)
            .disabled(onAlbumArtTap == nil && playDisabled)
            .opacity((onAlbumArtTap == nil && playDisabled) ? 0.45 : 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(.body.weight(.medium))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                artistLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                Button(action: playOrTogglePlayback) {
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)
                .disabled(playDisabled)
                .accessibilityLabel(playControlAccessibilityLabel)
            }
            .opacity(playDisabled ? 0.45 : 1)

            TrackHeartButton(track: track)

            TrackAddToPlaylistButton(track: track)

            Button {
                playOrTogglePlayback()
            } label: {
                Image(systemName: listPlayButtonShowsPause ? "pause.circle" : "play.circle")
                    .foregroundStyle(.secondary)
                    .contentTransition(
                        .symbolEffect(.replace.magic(fallback: .downUp.byLayer), options: .nonRepeating)
                    )
                    .animation(Self.listPlayIconAnimation, value: listPlayButtonShowsPause)
            }
            .buttonStyle(.plain)
            .disabled(playDisabled)
            .opacity(playDisabled ? 0.45 : 1)
            .accessibilityLabel(playControlAccessibilityLabel)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var artistLine: some View {
        if let onArtistTap, track.primaryArtistId != nil {
            Button(action: onArtistTap) {
                Text(track.primaryArtistName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        } else {
            Text(track.primaryArtistName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var trackThumbnail: some View {
        RemoteArtworkImage(url: track.smallImageURL, maxPixelSize: 96) { image in
            image
                .resizable()
                .scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } placeholder: {
            albumPlaceholder
        }
    }

    private var albumPlaceholder: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(.quaternary)
            .frame(width: 48, height: 48)
            .overlay { Image(systemName: "music.note").foregroundStyle(.secondary) }
    }
}
