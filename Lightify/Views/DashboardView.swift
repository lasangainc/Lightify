//
//  DashboardView.swift
//  Lightify
//

import SwiftUI

struct DashboardView: View {
    @Environment(AppSession.self) private var appSession
    @Environment(PlaybackViewModel.self) private var playback
    @State private var isRenamePlaylistAlertPresented = false
    @State private var renamePlaylistDraft = ""
    @State private var deletePlaylistTarget: SpotifyPlaylistItem?
    @State private var heroTint: (color: Color, gradientEnd: Color, luminance: CGFloat)?

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List {
                    Section {
                        sidebarRow(
                            title: "Home",
                            systemImage: "house.fill",
                            selection: .home
                        )
                        sidebarRow(
                            title: "Liked Songs",
                            systemImage: "music.note.list",
                            selection: .likedSongs
                        )
                        sidebarRow(
                            title: "Search",
                            systemImage: "magnifyingglass",
                            selection: .search
                        )
                    } header: {
                        Text("Library")
                    }

                    Section {
                        newPlaylistSidebarRow
                        ForEach(accessiblePlaylists) { playlist in
                            sidebarRow(
                                title: playlist.name,
                                systemImage: "music.note.list",
                                selection: .playlist(id: playlist.id)
                            )
                        }
                    } header: {
                        Text("Playlists")
                    }
                }

                Divider()

                sidebarProfileFooter
            }
            .navigationTitle("Library")
        } detail: {
            Group {
                if case let .artist(artistID, nameHint) = appSession.selectedLibrary {
                    ArtistView(artistID: artistID, nameHint: nameHint)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            if !playback.isWebPlayerReady {
                                Label("Connecting in-app Spotify player…", systemImage: "waveform")
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.blue.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }

                            if let loadErr = appSession.loadError {
                                Text(loadErr)
                                    .foregroundStyle(.red)
                                    .font(.callout)
                            }

                            switch appSession.selectedLibrary {
                            case .home:
                                likedSongsCarousel
                                recentlyPlayedSection
                            case .profile:
                                profileSection
                            case .likedSongs:
                                likedSongsTrackList
                            case .search:
                                searchSection
                            case .playlist:
                                selectedLibraryTracksSection
                            case .album:
                                albumLibraryTracksSection
                            case .artist:
                                EmptyView()
                            }
                        }
                        .padding(20)
                    }
                    .background(alignment: .top) {
                        libraryHeroGradient
                    }
                    .animation(.easeInOut(duration: 0.35), value: heroTint?.color)
                    .task(id: heroGradientTaskKey) {
                        await refreshHeroTint()
                    }
                }
            }
            .navigationTitle(appSession.detailNavigationTitle)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                NowPlayingControls()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                if appSession.canGoBackFromAlbum {
                    Button {
                        Task { await appSession.goBackFromAlbum() }
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .help("Go back")
                }
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    Task { await appSession.selectLibrary(.search) }
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .help("Open Search")
            }
            ToolbarItem(placement: .automatic) {
                Button("Sign out", role: .destructive) {
                    appSession.signOut()
                }
            }
            ToolbarItem(placement: .automatic) {
                Button("Refresh") {
                    Task { await appSession.reloadLibrary() }
                }
                .disabled(appSession.phase == .loadingContent)
            }
        }
        .sheet(isPresented: newPlaylistSheetBinding) {
            NewPlaylistSheet()
        }
        .alert("Playlist", isPresented: playlistErrorAlertBinding) {
            Button("OK") {
                appSession.playlistActionError = nil
            }
        } message: {
            Text(appSession.playlistActionError ?? "")
        }
        .alert("Rename Playlist", isPresented: renamePlaylistAlertBinding) {
            TextField("Name", text: renamePlaylistDraftBinding)
            Button("Cancel", role: .cancel) {
                isRenamePlaylistAlertPresented = false
            }
            Button("Rename") {
                guard let playlist = selectedPlaylist else { return }
                let newName = renamePlaylistDraft
                Task {
                    let didRename = await appSession.renamePlaylist(id: playlist.id, newName: newName)
                    if didRename {
                        isRenamePlaylistAlertPresented = false
                    }
                }
            }
            .disabled(renamePlaylistDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || appSession.isMutatingSelectedPlaylist)
        } message: {
            Text("Choose a new name for this playlist.")
        }
        .confirmationDialog(
            selectedPlaylistDeleteActionTitle,
            isPresented: deletePlaylistConfirmationBinding,
            titleVisibility: .visible
        ) {
            Button(selectedPlaylistDeleteActionTitle, role: .destructive) {
                guard let playlist = deletePlaylistTarget else { return }
                Task {
                    let didDelete = await appSession.deletePlaylist(id: playlist.id)
                    if didDelete {
                        deletePlaylistTarget = nil
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                deletePlaylistTarget = nil
            }
        } message: {
            Text(selectedPlaylistDeleteMessage)
        }
    }

    private var newPlaylistSheetBinding: Binding<Bool> {
        Binding(
            get: { appSession.isNewPlaylistSheetPresented },
            set: { newValue in
                if newValue {
                    appSession.isNewPlaylistSheetPresented = true
                } else {
                    appSession.dismissNewPlaylistSheet()
                }
            }
        )
    }

    /// Shows add-to-playlist failures when the create sheet isn’t visible (errors while creating stay in the sheet).
    private var playlistErrorAlertBinding: Binding<Bool> {
        Binding(
            get: { appSession.playlistActionError != nil && !appSession.isNewPlaylistSheetPresented },
            set: { newValue in
                if !newValue { appSession.playlistActionError = nil }
            }
        )
    }

    private var renamePlaylistAlertBinding: Binding<Bool> {
        Binding(
            get: { isRenamePlaylistAlertPresented && selectedPlaylist != nil },
            set: { newValue in
                isRenamePlaylistAlertPresented = newValue
                if !newValue {
                    renamePlaylistDraft = ""
                }
            }
        )
    }

    private var renamePlaylistDraftBinding: Binding<String> {
        Binding(
            get: { renamePlaylistDraft },
            set: { renamePlaylistDraft = $0 }
        )
    }

    private var deletePlaylistConfirmationBinding: Binding<Bool> {
        Binding(
            get: { deletePlaylistTarget != nil },
            set: { newValue in
                if !newValue {
                    deletePlaylistTarget = nil
                }
            }
        )
    }

    private var newPlaylistSidebarRow: some View {
        Button {
            appSession.presentNewPlaylistSheet()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.secondary)
                Text("New Playlist")
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
        .listRowBackground(Color.clear)
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

    private var searchSection: some View {
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
                            onArtistTap: artistTapAction(for: row.track),
                            onAlbumArtTap: albumTapAction(for: row.track)
                        )
                        Divider()
                    }
                }
            }
        }
    }

    /// Full list for the Liked Songs library page (hero matches playlist detail layout).
    private var likedSongsTrackList: some View {
        VStack(alignment: .leading, spacing: 16) {
            libraryHeroHeader

            if appSession.tracksForSelectedLibrary.isEmpty, appSession.loadError == nil {
                if appSession.phase != .loadingContent {
                    Text("No tracks in Liked Songs.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if !appSession.tracksForSelectedLibrary.isEmpty {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(appSession.tracksForSelectedLibrary) { track in
                        TrackRow(
                            track: track,
                            onPlay: { playback.playTrack(id: track.id) },
                            onArtistTap: artistTapAction(for: track),
                            onAlbumArtTap: albumTapAction(for: track)
                        )
                        .task(id: track.id) {
                            await appSession.loadMoreLikedSongsIfNeeded(currentTrackID: track.id)
                        }
                        Divider()
                    }

                    if appSession.isLoadingMoreLikedSongs {
                        HStack {
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                            Spacer()
                        }
                        .padding(.vertical, 12)
                    }
                }
            }
        }
    }

    private var selectedPlaylist: SpotifyPlaylistItem? {
        guard case .playlist(let id) = appSession.selectedLibrary else { return nil }
        return appSession.resolvedPlaylist(id: id)
    }

    private var selectedAlbumSelection: (id: String, nameHint: String?)? {
        guard case .album(let id, let hint) = appSession.selectedLibrary else { return nil }
        return (id, hint)
    }

    private var selectedResolvedAlbum: SpotifyAlbum? {
        guard let sel = selectedAlbumSelection else { return nil }
        return appSession.resolvedAlbum(id: sel.id)
    }

    /// Rename/delete only apply to playlists present in the user’s library.
    private var selectedPlaylistIsInUserLibrary: Bool {
        guard case .playlist(let id) = appSession.selectedLibrary else { return false }
        return appSession.playlists.contains { $0.id == id }
    }

    private var selectedPlaylistCanRename: Bool {
        guard let selectedPlaylist else { return false }
        return selectedPlaylist.isOwnedByCurrentUser(appSession.currentSpotifyUserId)
    }

    private var selectedPlaylistDeleteActionTitle: String {
        selectedPlaylistCanRename ? "Delete Playlist" : "Remove from Library"
    }

    private var selectedPlaylistDeleteMessage: String {
        guard let playlist = deletePlaylistTarget else { return "This action can’t be undone." }
        if playlist.isOwnedByCurrentUser(appSession.currentSpotifyUserId) {
            return "Delete \"\(playlist.name)\" from your library? Spotify removes it by unfollowing the playlist."
        }
        return "Remove \"\(playlist.name)\" from your library?"
    }

    private var libraryHeaderTitle: String {
        switch appSession.selectedLibrary {
        case .likedSongs:
            return "Liked Songs"
        case .playlist:
            return selectedPlaylist?.name ?? "Playlist"
        case .album:
            guard let sel = selectedAlbumSelection else { return "Album" }
            return selectedResolvedAlbum?.name ?? sel.nameHint ?? "Album"
        default:
            return ""
        }
    }

    /// Song count from loaded tracks, or playlist total from API metadata while tracks are still loading.
    private var libraryTrackCount: Int {
        let loaded = appSession.tracksForSelectedLibrary
        if case .likedSongs = appSession.selectedLibrary {
            return max(appSession.likedSongsTotalCount, loaded.count)
        }
        if !loaded.isEmpty { return loaded.count }
        if case .playlist = appSession.selectedLibrary {
            return selectedPlaylist?.tracks?.total ?? 0
        }
        if case .album = appSession.selectedLibrary {
            return selectedResolvedAlbum?.total_tracks ?? 0
        }
        return 0
    }

    private var libraryHeroShowsLoading: Bool {
        switch appSession.selectedLibrary {
        case .playlist:
            return appSession.isLoadingPlaylistTracks
        case .likedSongs:
            return appSession.phase == .loadingContent
        case .album:
            return appSession.isLoadingAlbumTracks
        default:
            return false
        }
    }

    private var libraryHeaderInfoLine: String {
        let n = libraryTrackCount
        let loaded = appSession.tracksForSelectedLibrary
        if libraryHeroShowsLoading && n == 0 {
            return "Loading…"
        }
        var parts: [String] = []
        if n == 0 {
            parts.append("0 songs")
        } else {
            parts.append(n == 1 ? "1 song" : "\(n) songs")
        }
        let totalMs = loaded.compactMap(\.duration_ms).reduce(0, +)
        let isFullyLoadedLikedSongs =
            appSession.selectedLibrary != .likedSongs || loaded.count >= max(appSession.likedSongsTotalCount, 0)
        if totalMs > 0, isFullyLoadedLikedSongs {
            parts.append(Self.formatPlaylistDuration(minutesRounded: (totalMs + 30_000) / 60_000))
        }
        return parts.joined(separator: " · ")
    }

    private var libraryHeaderDescription: String? {
        switch appSession.selectedLibrary {
        case .likedSongs:
            return "Your saved tracks"
        case .album:
            guard let album = selectedResolvedAlbum else { return nil }
            var parts: [String] = []
            let artists = album.primaryArtistLine
            if !artists.isEmpty {
                parts.append(artists)
            }
            if let y = album.releaseYearString {
                parts.append(y)
            }
            parts.append("Album")
            return parts.joined(separator: " · ")
        case .playlist:
            guard let raw = selectedPlaylist?.description?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
                return nil
            }
            if raw.contains("<") {
                return raw.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "&nbsp;", with: " ")
                    .replacingOccurrences(of: "&amp;", with: "&")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return raw
        default:
            return nil
        }
    }

    private var libraryHeroHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            libraryCoverHero

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(libraryHeaderTitle)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    if libraryHeroShowsLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                Text(libraryHeaderInfoLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let desc = libraryHeaderDescription {
                    Text(desc)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }

                libraryActionButtons
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var libraryActionButtons: some View {
        VStack(alignment: .leading, spacing: 10) {
            libraryPlayPillButton
            if case .playlist = appSession.selectedLibrary, selectedPlaylist != nil, selectedPlaylistIsInUserLibrary {
                playlistOptionsButton
            }
        }
    }

    private var selectedPlaylistIsActiveAndPlaying: Bool {
        guard case .playlist(let id) = appSession.selectedLibrary else { return false }
        guard let np = playback.nowPlaying, np.isPlaying else { return false }
        return np.contextURI == "spotify:playlist:\(id)"
    }

    private var selectedAlbumIsActiveAndPlaying: Bool {
        guard case .album(let id, _) = appSession.selectedLibrary else { return false }
        guard let np = playback.nowPlaying, np.isPlaying else { return false }
        return np.contextURI == "spotify:album:\(id)"
    }

    private var libraryContextIsActiveAndPlaying: Bool {
        selectedPlaylistIsActiveAndPlaying || selectedAlbumIsActiveAndPlaying
    }

    private var libraryPlayPillButton: some View {
        Button {
            if libraryContextIsActiveAndPlaying {
                playback.playPause()
            } else {
                playLibrarySelection()
            }
        } label: {
            Label(
                libraryContextIsActiveAndPlaying ? "Pause" : "Play",
                systemImage: libraryContextIsActiveAndPlaying ? "pause.fill" : "play.fill"
            )
                .font(.subheadline.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color("AccentColor"))
        .clipShape(Capsule())
        .disabled(!libraryPlayActionEnabled)
        .opacity(libraryPlayActionEnabled ? 1 : 0.45)
    }

    private var playlistOptionsButton: some View {
        Menu {
            if selectedPlaylistCanRename {
                Button("Rename") {
                    renamePlaylistDraft = selectedPlaylist?.name ?? ""
                    isRenamePlaylistAlertPresented = true
                }
            }
            Button(selectedPlaylistDeleteActionTitle, role: .destructive) {
                deletePlaylistTarget = selectedPlaylist
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32, alignment: .center)
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .disabled(appSession.isMutatingSelectedPlaylist)
        .opacity(appSession.isMutatingSelectedPlaylist ? 0.45 : 1)
        .help("Playlist options")
    }

    private var libraryPlayActionEnabled: Bool {
        guard playback.isWebPlayerReady else { return false }
        switch appSession.selectedLibrary {
        case .likedSongs:
            return !appSession.likedSongs.isEmpty && appSession.phase != .loadingContent
        case .playlist:
            return true
        case .album:
            return true
        default:
            return false
        }
    }

    private func playLibrarySelection() {
        switch appSession.selectedLibrary {
        case .likedSongs:
            playback.playTrackList(trackIDs: appSession.likedSongIDsInOrder)
        case .playlist(let id):
            playback.playContextURI("spotify:playlist:\(id)")
        case .album(let id, _):
            playback.playContextURI("spotify:album:\(id)")
        default:
            break
        }
    }

    private static func formatPlaylistDuration(minutesRounded: Int) -> String {
        guard minutesRounded > 0 else { return "0 min" }
        if minutesRounded >= 60 {
            let h = minutesRounded / 60
            let m = minutesRounded % 60
            return m > 0 ? "\(h) hr \(m) min" : "\(h) hr"
        }
        return "\(minutesRounded) min"
    }

    private var selectedLibraryTracksSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            libraryHeroHeader

            if appSession.isPlaylistTrackListForbidden {
                Text(AppSession.playlistTracksUnavailableMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            } else if appSession.tracksForSelectedLibrary.isEmpty, !appSession.isLoadingPlaylistTracks, appSession.loadError == nil {
                Text("No tracks in this playlist.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if !appSession.tracksForSelectedLibrary.isEmpty {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(appSession.tracksForSelectedLibrary) { track in
                        TrackRow(
                            track: track,
                            onPlay: { playback.playTrack(id: track.id) },
                            onArtistTap: artistTapAction(for: track),
                            onAlbumArtTap: albumTapAction(for: track)
                        )
                        Divider()
                    }
                }
            }
        }
    }

    private var albumLibraryTracksSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            libraryHeroHeader

            if let warning = appSession.albumCatalogWarning {
                Text(warning)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if appSession.tracksForSelectedLibrary.isEmpty, !appSession.isLoadingAlbumTracks, appSession.loadError == nil {
                Text("No tracks on this album.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if !appSession.tracksForSelectedLibrary.isEmpty {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(appSession.tracksForSelectedLibrary) { track in
                        TrackRow(
                            track: track,
                            onPlay: { playback.playTrack(id: track.id) },
                            onArtistTap: artistTapAction(for: track),
                            onAlbumArtTap: albumTapAction(for: track)
                        )
                        Divider()
                    }
                }
            }
        }
    }

    private var libraryHasHeroGradient: Bool {
        switch appSession.selectedLibrary {
        case .likedSongs, .playlist, .album:
            return true
        default:
            return false
        }
    }

    private var heroGradientTaskKey: String {
        guard libraryHasHeroGradient else { return "none" }
        return libraryCoverImageURL?.absoluteString ?? "placeholder"
    }

    @ViewBuilder
    private var libraryHeroGradient: some View {
        if libraryHasHeroGradient, let tint = heroTint {
            LinearGradient(
                colors: [
                    tint.color.opacity(0.72),
                    tint.gradientEnd.opacity(0.32),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 440)
            .frame(maxWidth: .infinity)
            .blur(radius: 32)
            .opacity(0.95)
            .allowsHitTesting(false)
            .transition(.opacity)
            .ignoresSafeArea(edges: .top)
        }
    }

    @MainActor
    private func refreshHeroTint() async {
        guard libraryHasHeroGradient, let url = libraryCoverImageURL else {
            heroTint = nil
            return
        }
        do {
            let image = try await ArtworkPipeline.shared.image(for: url, maxPixelSize: 96)
            heroTint = ArtworkColorSampler.tint(from: image)
        } catch {
            heroTint = nil
        }
    }

    private var libraryCoverImageURL: URL? {
        switch appSession.selectedLibrary {
        case .likedSongs:
            return appSession.likedSongs.first?.largestAlbumImageURL
        case .playlist:
            return selectedPlaylist?.coverURL
        case .album:
            return selectedResolvedAlbum?.largestCoverURL
        default:
            return nil
        }
    }

    private var libraryCoverHero: some View {
        let side: CGFloat = 140
        return Group {
            RemoteArtworkImage(url: libraryCoverImageURL, maxPixelSize: side * 2) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                libraryCoverPlaceholder
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var libraryCoverPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(.quaternary)
            .overlay {
                Image(systemName: libraryCoverPlaceholderSymbol)
                    .foregroundStyle(.secondary)
            }
    }

    private var libraryCoverPlaceholderSymbol: String {
        switch appSession.selectedLibrary {
        case .likedSongs:
            return "heart.fill"
        case .album:
            return "square.stack.fill"
        default:
            return "music.note"
        }
    }

    // MARK: - Profile

    private var profileSection: some View {
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
            profileAvatar(size: 128)
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

    private var sidebarProfileFooter: some View {
        Button {
            Task { await appSession.selectLibrary(.profile) }
        } label: {
            HStack(spacing: 10) {
                profileAvatar(size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(appSession.currentUserProfile?.resolvedDisplayName ?? "Spotify")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text("View profile")
                        .font(.caption)
                        .foregroundStyle(isSelected(.profile) ? .white.opacity(0.88) : .secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected(.profile) ? Color("AccentColor") : Color(nsColor: .controlBackgroundColor))
            )
            .foregroundStyle(isSelected(.profile) ? .white : .primary)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    private var profilePlaceholder: some View {
        Circle()
            .fill(Color.secondary.opacity(0.2))
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
    }

    @ViewBuilder
    private func profileAvatar(size: CGFloat) -> some View {
        RemoteArtworkImage(url: appSession.currentUserProfile?.profileImageURL, maxPixelSize: size * 2) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            profilePlaceholder
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var accessiblePlaylists: [SpotifyPlaylistItem] {
        appSession.playlists.filter { !$0.isLikelyLikedSongsMirror }
    }

    private func sidebarRow(title: String, systemImage: String, selection: AppSession.LibrarySelection) -> some View {
        Button {
            Task { await appSession.selectLibrary(selection) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundStyle(isSelected(selection) ? .white : .secondary)
                Text(title)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected(selection) ? Color("AccentColor") : Color.clear)
            )
            .foregroundStyle(isSelected(selection) ? .white : .primary)
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
        .listRowBackground(Color.clear)
    }

    private func isSelected(_ selection: AppSession.LibrarySelection) -> Bool {
        appSession.selectedLibrary == selection
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
            .frame(width: 48, height: 48)
            .overlay { Image(systemName: "music.note.list").foregroundStyle(.secondary) }
    }
}

// MARK: - Carousel card

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

#Preview {
    DashboardView()
        .environment(AppSession())
        .environment(PlaybackViewModel())
}
