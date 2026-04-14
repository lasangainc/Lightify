//
//  TrackRow.swift
//  Lightify
//

import SwiftUI

struct TrackAddToPlaylistButton: View {
    let track: SpotifyTrack
    @Environment(AppSession.self) private var appSession

    private var isBusy: Bool {
        appSession.modifiablePlaylists.contains {
            appSession.isAddingTrack(track.id, toPlaylist: $0.id)
        }
    }

    var body: some View {
        Menu {
            ForEach(appSession.modifiablePlaylists) { playlist in
                Button {
                    Task {
                        await appSession.addTrackToPlaylist(trackID: track.id, playlistID: playlist.id)
                    }
                } label: {
                    Text(playlist.name)
                }
                .disabled(appSession.isAddingTrack(track.id, toPlaylist: playlist.id))
            }

            if !appSession.modifiablePlaylists.isEmpty {
                Divider()
            }

            Button {
                appSession.presentNewPlaylistSheet(trackToAddFirst: track)
            } label: {
                Label("New Playlist…", systemImage: "plus.square.on.square")
            }
        } label: {
            ZStack {
                Image(systemName: "plus")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .opacity(isBusy ? 0 : 1)
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.secondary)
                }
            }
            .frame(width: 22, height: 22)
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .tint(.secondary)
        .disabled(isBusy)
        .help("Add to playlist")
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

    var body: some View {
        HStack(spacing: 12) {
            Button {
                if let onAlbumArtTap {
                    onAlbumArtTap()
                } else {
                    onPlay()
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
                Button(action: onPlay) {
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)
                .disabled(playDisabled)
                .accessibilityLabel("Play \(track.name) by \(track.primaryArtistName)")
            }
            .opacity(playDisabled ? 0.45 : 1)

            TrackHeartButton(track: track)

            TrackAddToPlaylistButton(track: track)

            Button(action: onPlay) {
                Image(systemName: "play.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(playDisabled)
            .opacity(playDisabled ? 0.45 : 1)
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
