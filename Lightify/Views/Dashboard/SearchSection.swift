//
//  SearchSection.swift
//  Lightify
//

import SwiftUI

struct SearchSection: View {
    @Environment(AppSession.self) private var appSession
    @Environment(PlaybackViewModel.self) private var playback

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Search Spotify")
                .font(.title2.weight(.semibold))

            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    TextField(
                        "Artist, song, or album",
                        text: Binding(
                            get: { appSession.searchQueryText },
                            set: { appSession.searchQueryText = $0 }
                        )
                    )
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: appSession.searchQueryText) { _, newValue in
                        if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Task { await appSession.searchCatalog(query: "") }
                        }
                    }
                    .onSubmit {
                        Task { await appSession.searchCatalog(query: appSession.searchQueryText) }
                    }
                    .glassEffect(.regular.interactive(), in: Capsule())

                    Button {
                        Task { await appSession.searchCatalog(query: appSession.searchQueryText) }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .disabled(appSession.isSearching)
                    .opacity(appSession.isSearching ? 0.45 : 1)
                    .accessibilityLabel("Search")
                    .help("Search")
                }
            }

            if appSession.isSearching {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Searching…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let searchErr = appSession.searchError {
                Text(searchErr)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            let trimmedQuery = appSession.searchQueryText.trimmingCharacters(in: .whitespacesAndNewlines)
            let snap = appSession.catalogSearch

            if !appSession.isSearching, trimmedQuery.isEmpty {
                Text("Type a query and press Search or Return to browse songs, artists, albums, and playlists.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if !appSession.isSearching,
                      snap.isEmpty,
                      appSession.searchError == nil,
                      !trimmedQuery.isEmpty
            {
                Text("No results found.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if !snap.isEmpty, appSession.searchError == nil {
                Picker("Result type", selection: searchTabBinding) {
                    ForEach(AppSession.SearchTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Group {
                    switch appSession.selectedSearchTab {
                    case .all:
                        searchAllTab(snapshot: snap)
                    case .songs:
                        searchSongsList(tracks: snap.tracks)
                    case .artists:
                        searchArtistsList(artists: snap.artists)
                    case .albums:
                        searchAlbumsList(albums: snap.albums)
                    case .playlists:
                        searchPlaylistsList(playlists: snap.playlists)
                    }
                }
            }
        }
    }

    private var searchTabBinding: Binding<AppSession.SearchTab> {
        Binding(
            get: { appSession.selectedSearchTab },
            set: { appSession.selectedSearchTab = $0 }
        )
    }

    private func openArtist(id: String, nameHint: String?) {
        Task { await appSession.selectLibrary(.artist(id: id, nameHint: nameHint)) }
    }

    private func openPlaylistFromSearch(_ playlist: SpotifyPlaylistItem) {
        Task { await appSession.openPlaylist(playlist) }
    }

    private func openAlbumFromSearch(_ album: SpotifySearchAlbumItem) {
        Task { await appSession.openAlbumFromSearch(album) }
    }

    private func artistTapAction(for track: SpotifyTrack) -> (() -> Void)? {
        guard let aid = track.primaryArtistId else { return nil }
        let hint = track.artists.first?.name
        return { openArtist(id: aid, nameHint: hint) }
    }

    private func albumTapAction(for track: SpotifyTrack) -> (() -> Void)? {
        guard !track.id.isEmpty else { return nil }
        return {
            Task { await appSession.openAlbum(from: track) }
        }
    }

    private func searchAllTab(snapshot: SpotifyCatalogSearchSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            if let top = snapshot.topResult {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Top result")
                        .font(.headline)
                    searchTopResultCard(top)
                }
            }

            if !snapshot.tracks.isEmpty {
                searchSubsection(title: "Songs", items: Array(snapshot.tracks.prefix(3))) { track in
                    TrackRow(
                        track: track,
                        onPlay: { playback.playTrack(id: track.id) },
                        playDisabled: !playback.isWebPlayerReady,
                        onArtistTap: artistTapAction(for: track),
                        onAlbumArtTap: albumTapAction(for: track)
                    )
                }
            }

            if !snapshot.artists.isEmpty {
                searchSubsection(title: "Artists", items: Array(snapshot.artists.prefix(3))) { artist in
                    searchArtistRowWithPlay(artist: artist)
                }
            }

            if !snapshot.albums.isEmpty {
                searchSubsection(title: "Albums", items: Array(snapshot.albums.prefix(3))) { album in
                    searchAlbumRowWithOpen(album: album)
                }
            }

            if !snapshot.playlists.isEmpty {
                searchSubsection(title: "Playlists", items: Array(snapshot.playlists.prefix(3))) { playlist in
                    Button {
                        openPlaylistFromSearch(playlist)
                    } label: {
                        SearchPlaylistRow(playlist: playlist)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func searchSubsection<Item: Identifiable, Row: View>(
        title: String,
        items: [Item],
        @ViewBuilder row: @escaping (Item) -> Row
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(items) { item in
                    row(item)
                    Divider()
                }
            }
        }
    }

    @ViewBuilder
    private func searchTopResultCard(_ top: SpotifySearchTopResult) -> some View {
        switch top {
        case let .track(track):
            ZStack(alignment: .topTrailing) {
                Button {
                    playback.playTrack(id: track.id)
                } label: {
                    SearchTopResultCardLayout(
                        title: track.name,
                        subtitle: track.primaryArtistName,
                        imageURL: track.smallImageURL ?? track.largestAlbumImageURL,
                        footnote: "Song",
                        systemImage: "music.note"
                    )
                }
                .buttonStyle(.plain)
                .disabled(!playback.isWebPlayerReady)
                .opacity(playback.isWebPlayerReady ? 1 : 0.45)

                TrackHeartButton(track: track)
                    .padding(10)
            }
        case let .artist(artist):
            ZStack(alignment: .topTrailing) {
                Button {
                    openArtist(id: artist.id, nameHint: artist.name)
                } label: {
                    SearchTopResultCardLayout(
                        title: artist.name,
                        subtitle: "Artist",
                        imageURL: artist.profileImageURL,
                        footnote: "Artist",
                        systemImage: "person.fill"
                    )
                }
                .buttonStyle(.plain)

                Button {
                    playback.playContextURI("spotify:artist:\(artist.id)")
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .disabled(!playback.isWebPlayerReady)
                .opacity(playback.isWebPlayerReady ? 1 : 0.45)
                .padding(10)
            }
        case let .album(album):
            ZStack(alignment: .topTrailing) {
                Button {
                    openAlbumFromSearch(album)
                } label: {
                    SearchTopResultCardLayout(
                        title: album.name,
                        subtitle: album.primaryArtistName,
                        imageURL: album.coverURL,
                        footnote: "Album",
                        systemImage: "square.stack.fill"
                    )
                }
                .buttonStyle(.plain)

                Button {
                    playback.playContextURI("spotify:album:\(album.id)")
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .disabled(!playback.isWebPlayerReady)
                .opacity(playback.isWebPlayerReady ? 1 : 0.45)
                .padding(10)
            }
        case let .playlist(pl):
            Button {
                openPlaylistFromSearch(pl)
            } label: {
                SearchTopResultCardLayout(
                    title: pl.name,
                    subtitle: (pl.owner?.id).map { "By \($0)" } ?? "Playlist",
                    imageURL: pl.coverURL,
                    footnote: "Playlist",
                    systemImage: "music.note.list"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func searchSongsList(tracks: [SpotifyTrack]) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(tracks) { track in
                TrackRow(
                    track: track,
                    onPlay: { playback.playTrack(id: track.id) },
                    playDisabled: !playback.isWebPlayerReady,
                    onArtistTap: artistTapAction(for: track),
                    onAlbumArtTap: albumTapAction(for: track)
                )
                Divider()
            }
        }
    }

    private func searchArtistRowWithPlay(artist: SpotifySearchArtistItem) -> some View {
        HStack(spacing: 12) {
            Button {
                openArtist(id: artist.id, nameHint: artist.name)
            } label: {
                SearchArtistRow(artist: artist)
            }
            .buttonStyle(.plain)

            Button {
                playback.playContextURI("spotify:artist:\(artist.id)")
            } label: {
                Image(systemName: "play.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(!playback.isWebPlayerReady)
            .opacity(playback.isWebPlayerReady ? 1 : 0.45)
        }
    }

    private func searchArtistsList(artists: [SpotifySearchArtistItem]) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(artists) { artist in
                searchArtistRowWithPlay(artist: artist)
                Divider()
            }
        }
    }

    private func searchAlbumsList(albums: [SpotifySearchAlbumItem]) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(albums) { album in
                searchAlbumRowWithOpen(album: album)
                Divider()
            }
        }
    }

    private func searchAlbumRowWithOpen(album: SpotifySearchAlbumItem) -> some View {
        HStack(spacing: 12) {
            Button {
                openAlbumFromSearch(album)
            } label: {
                SearchAlbumRow(album: album, showsTrailingPlayGlyph: false)
            }
            .buttonStyle(.plain)

            Button {
                playback.playContextURI("spotify:album:\(album.id)")
            } label: {
                Image(systemName: "play.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(!playback.isWebPlayerReady)
            .opacity(playback.isWebPlayerReady ? 1 : 0.45)
        }
    }

    private func searchPlaylistsList(playlists: [SpotifyPlaylistItem]) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(playlists) { playlist in
                Button {
                    openPlaylistFromSearch(playlist)
                } label: {
                    SearchPlaylistRow(playlist: playlist)
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
    }
}

// MARK: - Search rows

private struct SearchTopResultCardLayout: View {
    let title: String
    let subtitle: String
    let imageURL: URL?
    let footnote: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            RemoteArtworkImage(url: imageURL, maxPixelSize: 160) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                placeholderArt
            }
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 6) {
                Text(footnote.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.leading)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(.quaternary.opacity(0.45))
        }
    }

    private var placeholderArt: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(.quaternary)
            .overlay {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
    }
}

private struct SearchArtistRow: View {
    let artist: SpotifySearchArtistItem

    var body: some View {
        HStack(spacing: 12) {
            RemoteArtworkImage(url: artist.profileImageURL, maxPixelSize: 96) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
            } placeholder: {
                avatarPlaceholder
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(artist.name)
                    .font(.body.weight(.medium))
                Text("Artist")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(.quaternary)
            .frame(width: 48, height: 48)
            .overlay {
                Image(systemName: "person.fill")
                    .foregroundStyle(.secondary)
            }
    }
}

private struct SearchAlbumRow: View {
    let album: SpotifySearchAlbumItem
    /// When false, omit the decorative play icon (caller supplies its own play control).
    var showsTrailingPlayGlyph: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            RemoteArtworkImage(url: album.coverURL, maxPixelSize: 96) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } placeholder: {
                artPlaceholder
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(album.name)
                    .font(.body.weight(.medium))
                Text(album.primaryArtistName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if showsTrailingPlayGlyph {
                Image(systemName: "play.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private var artPlaceholder: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(.quaternary)
            .frame(width: 48, height: 48)
            .overlay { Image(systemName: "square.stack.fill").foregroundStyle(.secondary) }
    }
}

private struct SearchPlaylistRow: View {
    let playlist: SpotifyPlaylistItem

    var body: some View {
        HStack(spacing: 12) {
            RemoteArtworkImage(url: playlist.coverURL, maxPixelSize: 96) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } placeholder: {
                artPlaceholder
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .font(.body.weight(.medium))
                if let owner = playlist.owner, let ownerId = owner.id {
                    Text("By \(ownerId)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "play.circle")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private var artPlaceholder: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(.quaternary)
            .overlay { Image(systemName: "music.note.list").foregroundStyle(.secondary) }
    }
}
