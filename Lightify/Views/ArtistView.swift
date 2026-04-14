//
//  ArtistView.swift
//  Lightify
//

import SwiftUI

/// Artist catalog screen: profile image, name, play in artist context, and top tracks.
struct ArtistView: View {
    let artistID: String
    var nameHint: String?

    @Environment(AppSession.self) private var appSession
    @Environment(PlaybackViewModel.self) private var playback

    @State private var profile: SpotifyArtistProfile?
    @State private var topTracks: [SpotifyTrack] = []
    @State private var loadError: String?
    @State private var isLoading = true

    private var displayName: String {
        profile?.name ?? nameHint ?? "Artist"
    }

    /// True when at least one catalog request succeeded (403 on the other call is a warning, not a total failure).
    private var hasPartialCatalog: Bool {
        profile != nil || !topTracks.isEmpty
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
                if let loadError {
                    Text(loadError)
                        .foregroundStyle(hasPartialCatalog ? Color.orange : Color.red)
                        .font(.callout)
                }
                if !topTracks.isEmpty {
                    Text("Popular")
                        .font(.title3.weight(.semibold))
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(topTracks) { track in
                            TrackRow(
                                track: track,
                                onPlay: { playback.playTrack(id: track.id) },
                                playDisabled: !playback.isWebPlayerReady
                            )
                            Divider()
                        }
                    }
                } else if !isLoading, loadError == nil {
                    Text("No top tracks for this artist.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .task(id: artistID) {
            await loadArtistContent()
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Group {
                if let url = profile?.largestImageURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            Circle().fill(.quaternary)
                        case let .success(image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            Circle().fill(.quaternary)
                                .overlay { Image(systemName: "person.fill").foregroundStyle(.secondary) }
                        @unknown default:
                            Circle().fill(.quaternary)
                        }
                    }
                } else {
                    Circle()
                        .fill(.quaternary)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: 160, height: 160)
            .clipShape(Circle())

            Text(displayName)
                .font(.title.weight(.bold))

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

    private func loadArtistContent() async {
        isLoading = true
        loadError = nil
        profile = nil
        topTracks = []

        do {
            let result = try await appSession.loadArtistCatalog(artistID: artistID)
            profile = result.0
            topTracks = result.1
            loadError = result.2
        } catch {
            loadError = error.localizedDescription
        }

        isLoading = false
    }
}
