//
//  HomeAndProfileSection.swift
//  Lightify
//

import SwiftUI

// MARK: - Home

struct HomeSection: View {
    @Environment(AppSession.self) private var appSession
    @Environment(PlaybackViewModel.self) private var playback

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            likedSongsCarousel
            recentlyPlayedSection
        }
    }

    private var likedSongsCarousel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Liked songs")
                .font(.title2.weight(.semibold))

            if appSession.likedSongs.isEmpty {
                Text("No liked songs yet — save tracks in Spotify and refresh.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(appSession.likedSongs) { track in
                            LikedSongCarouselCard(
                                track: track,
                                onPlay: {
                                    playback.playTrack(id: track.id)
                                },
                                onAlbumArtTap: {
                                    Task { await appSession.openAlbum(from: track) }
                                }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var recentlyPlayedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recently played")
                .font(.title2.weight(.semibold))

            if appSession.recentlyPlayed.isEmpty {
                Text("Nothing here yet — play something in Spotify and refresh.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(appSession.recentlyPlayed) { row in
                        TrackRow(
                            track: row.track,
                            onPlay: { playback.playTrack(id: row.track.id) },
                            onArtistTap: DashboardTrackActions.artistTapAction(appSession: appSession, for: row.track),
                            onAlbumArtTap: DashboardTrackActions.albumTapAction(appSession: appSession, for: row.track)
                        )
                        Divider()
                    }
                }
            }
        }
    }
}

private struct LikedSongCarouselCard: View {
    let track: SpotifyTrack
    let onPlay: () -> Void
    var onAlbumArtTap: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Button {
                    if let onAlbumArtTap {
                        onAlbumArtTap()
                    } else {
                        onPlay()
                    }
                } label: {
                    carouselArt
                }
                .buttonStyle(.plain)

                TrackHeartButton(track: track)
                    .padding(8)
            }

            Button(action: onPlay) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.primary)
                        .frame(width: 140, alignment: .leading)

                    Text(track.primaryArtistName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: 140, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var carouselArt: some View {
        Group {
            RemoteArtworkImage(url: track.largestAlbumImageURL, maxPixelSize: 280) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .overlay { Image(systemName: "music.note").foregroundStyle(.secondary) }
            }
        }
        .frame(width: 140, height: 140)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Profile

struct ProfileSection: View {
    @Environment(AppSession.self) private var appSession

    var body: some View {
        VStack(spacing: 28) {
            if let profile = appSession.currentUserProfile {
                profileHero(profile)
                profileStatsRow(profile)
                profileAboutCard(profile)

                if let spotifyURL = profile.spotifyProfileURL {
                    Link(destination: spotifyURL) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Open in Spotify")
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .glassEffect(.regular.interactive(), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            } else {
                ContentUnavailableView(
                    "Profile unavailable",
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    description: Text("Refresh to try loading your Spotify profile again.")
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func profileHero(_ profile: SpotifyCurrentUser) -> some View {
        VStack(spacing: 16) {
            DashboardProfileAvatar(size: 128)
                .shadow(color: .black.opacity(0.35), radius: 24, y: 8)

            Text(profile.resolvedDisplayName)
                .font(.system(size: 32, weight: .bold))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private func profileStatsRow(_ profile: SpotifyCurrentUser) -> some View {
        HStack(spacing: 0) {
            if let followers = profile.followers?.total {
                profileStat(value: "\(followers)", label: "Followers")
            }

            if !appSession.playlists.isEmpty {
                profileStat(value: "\(appSession.playlists.count)", label: "Playlists")
            }

            if appSession.likedSongsTotalCount > 0 {
                profileStat(value: "\(appSession.likedSongsTotalCount)", label: "Liked Songs")
            }
        }
        .frame(maxWidth: 480)
    }

    private func profileStat(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func profileAboutCard(_ profile: SpotifyCurrentUser) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let email = profile.email, !email.isEmpty {
                profileDetailRow(icon: "envelope.fill", title: "Email", detail: email)
            }
            if let country = profile.country, !country.isEmpty {
                profileDetailRow(icon: "globe", title: "Country", detail: countryName(from: country))
            }
            profileDetailRow(icon: "person.text.rectangle", title: "Username", detail: profile.id)
            if let uri = profile.uri, !uri.isEmpty {
                profileDetailRow(icon: "link", title: "Spotify URI", detail: uri)
            }
            if let filterEnabled = profile.explicit_content?.filter_enabled {
                profileDetailRow(
                    icon: filterEnabled ? "eye.slash.fill" : "eye.fill",
                    title: "Explicit Content",
                    detail: filterEnabled ? "Filtered" : "Allowed"
                )
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: 480)
    }

    private func profileDetailRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(detail)
                    .font(.subheadline.weight(.medium))
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private func countryName(from code: String) -> String {
        Locale.current.localizedString(forRegionCode: code) ?? code
    }
}
