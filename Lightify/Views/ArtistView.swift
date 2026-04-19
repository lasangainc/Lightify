//
//  ArtistView.swift
//  Lightify
//

import SwiftUI

/// Artist catalog screen: profile image, name, play in artist context, popular tracks, and fallbacks.
struct ArtistView: View {
    let artistID: String
    var nameHint: String?

    @Environment(AppSession.self) private var appSession
    @Environment(PlaybackViewModel.self) private var playback
    @Environment(\.colorScheme) private var colorScheme

    @State private var profile: SpotifyArtistProfile?
    @State private var avatarPalette: ArtworkPalette?
    @State private var topTracks: [SpotifyTrack] = []
    @State private var artistAlbums: [SpotifyAlbum] = []
    @State private var loadError: String?
    @State private var isLoading = true

    private var displayName: String {
        let n = profile?.name ?? nameHint
        let trimmed = n?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Artist" : trimmed
    }

    private var followersLabel: String? {
        guard let total = profile?.followers?.total else { return nil }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        let s = f.string(from: NSNumber(value: total)) ?? "\(total)"
        return "\(s) followers"
    }

    /// Stable rows for `ForEach` (album ids deduped in `AppSession`).
    private var identifiedAlbumRows: [IdentifiedArtistAlbum] {
        artistAlbums.compactMap { album in
            guard let id = album.id, !id.isEmpty else { return nil }
            return IdentifiedArtistAlbum(id: id, album: album)
        }
    }

    /// Same light/dark mapping as `LibraryHeroGradient` / playlist–album hero tint.
    private var avatarGlowStops: (color: Color, gradientEnd: Color)? {
        guard let palette = avatarPalette else { return nil }
        return HeroArtworkTint.tintStop(for: palette, colorScheme: colorScheme)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero
                if isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                if !topTracks.isEmpty {
                    Text("Popular")
                        .font(.title3.weight(.semibold))
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(topTracks) { track in
                            TrackRow(
                                track: track,
                                onPlay: { playback.playTrack(id: track.id) },
                                playDisabled: !playback.isWebPlayerReady,
                                onAlbumArtTap: {
                                    Task { await appSession.openAlbum(from: track) }
                                }
                            )
                            Divider()
                        }
                    }
                }
                if !artistAlbums.isEmpty {
                    Text("Discography")
                        .font(.title3.weight(.semibold))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(identifiedAlbumRows) { row in
                                Button {
                                    Task {
                                        await appSession.openAlbum(id: row.id, nameHint: row.album.name, seedAlbum: row.album)
                                    }
                                } label: {
                                    ArtistAlbumCell(album: row.album)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                if !isLoading, loadError == nil, topTracks.isEmpty, artistAlbums.isEmpty {
                    Text("No tracks or releases found for this artist in your market.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .task(id: artistID) {
            await loadArtistContent()
        }
        .task(id: profile?.largestImageURL?.absoluteString ?? "") {
            await refreshAvatarPalette()
        }
        .alert("Artist", isPresented: artistLoadErrorAlertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(loadError ?? "")
        }
    }

    private var artistLoadErrorAlertBinding: Binding<Bool> {
        Binding(
            get: { loadError != nil },
            set: { newValue in
                if !newValue { loadError = nil }
            }
        )
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            artistAvatarHero

            Text(displayName)
                .font(.title.weight(.bold))

            if let genres = profile?.genres, !genres.isEmpty {
                Text(genres.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            HStack(spacing: 10) {
                if let followersLabel {
                    Text(followersLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let pop = profile?.popularity {
                    Text("Popularity \(pop)/100")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let url = profile?.spotifyWebURL {
                Link(destination: url) {
                    Label("Open in Spotify", systemImage: "arrow.up.right.square")
                        .font(.subheadline.weight(.medium))
                }
            }

            Button {
                playback.playContextURI("spotify:artist:\(artistID)")
            } label: {
                Label("Play", systemImage: "play.fill")
                    .font(.subheadline.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color("AccentColor"))
            .clipShape(Capsule())
            .disabled(!playback.isWebPlayerReady)
            .opacity(playback.isWebPlayerReady ? 1 : 0.45)
        }
    }

    /// Circular PFP with artwork-colored glow (matches playlist/album `HeroArtworkTint` behavior).
    private var artistAvatarHero: some View {
        let side: CGFloat = 160
        let halo: CGFloat = 28
        let stops = avatarGlowStops

        return ZStack {
            if let stop = stops {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                stop.color.opacity(colorScheme == .light ? 0.38 : 0.32),
                                stop.gradientEnd.opacity(colorScheme == .light ? 0.14 : 0.12),
                                .clear,
                            ],
                            center: .center,
                            startRadius: side * 0.25,
                            endRadius: side * 0.72 + halo
                        )
                    )
                    .frame(width: side + halo * 2, height: side + halo * 2)
                    .blur(radius: colorScheme == .light ? 16 : 14)
                    .allowsHitTesting(false)
            }

            RemoteArtworkImage(url: profile?.largestImageURL, maxPixelSize: 512) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Circle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
            }
            .frame(width: side, height: side)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
            }
            .modifier(ArtistAvatarGlowShadows(stops: stops, colorScheme: colorScheme))
        }
        .padding(.bottom, stops == nil ? 0 : 6)
    }

    @MainActor
    private func refreshAvatarPalette() async {
        avatarPalette = nil
        guard let url = profile?.largestImageURL else { return }
        do {
            let image = try await ArtworkPipeline.shared.image(for: url, maxPixelSize: 96)
            avatarPalette = ArtworkColorSampler.palette(from: image)
        } catch {
            avatarPalette = nil
        }
    }

    private func loadArtistContent() async {
        isLoading = true
        loadError = nil
        profile = nil
        avatarPalette = nil
        topTracks = []
        artistAlbums = []

        do {
            let result = try await appSession.loadArtistCatalog(artistID: artistID, nameHint: nameHint)
            profile = result.0
            topTracks = result.1
            artistAlbums = result.2
            loadError = result.3
        } catch {
            loadError = error.localizedDescription
        }

        isLoading = false
    }
}

/// Two-layer shadow using the same primary/secondary pair as `LibraryHeroGradient` / `HeroArtworkTint`.
private struct ArtistAvatarGlowShadows: ViewModifier {
    let stops: (color: Color, gradientEnd: Color)?
    let colorScheme: ColorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        if let stop = stops {
            let light = colorScheme == .light
            content
                .shadow(color: stop.color.opacity(light ? 0.44 : 0.5), radius: light ? 18 : 15, y: 3)
                .shadow(color: stop.gradientEnd.opacity(light ? 0.28 : 0.34), radius: light ? 30 : 24, y: 1)
        } else {
            content
        }
    }
}

// MARK: - Discography cell

private struct IdentifiedArtistAlbum: Identifiable {
    let id: String
    let album: SpotifyAlbum
}

private struct ArtistAlbumCell: View {
    let album: SpotifyAlbum

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RemoteArtworkImage(url: album.largestCoverURL, maxPixelSize: 240) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "opticaldisc")
                            .foregroundStyle(.secondary)
                    }
            }
            .frame(width: 120, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Text(album.name)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(width: 120, alignment: .leading)
            if let y = album.releaseYearString {
                Text(y)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
