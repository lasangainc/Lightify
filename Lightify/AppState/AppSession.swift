//
//  AppSession.swift
//  Lightify
//

import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AppSession {
    /// Profile from `GET /v1/me` — used for UI and playlist `owner.id` (edit vs read-only heuristics).
    private(set) var currentUserProfile: SpotifyCurrentUser?

    var currentSpotifyUserId: String? { currentUserProfile?.id }

    enum Phase: Equatable {
        case bootstrapping
        case needsLogin
        case loadingContent
        case ready
    }

    /// Sidebar + detail: Home overview, Liked Songs (saved tracks), catalog search, a user playlist, album detail, or an artist detail screen.
    enum LibrarySelection: Equatable, Hashable, Identifiable {
        case home
        case profile
        case likedSongs
        case search
        case playlist(id: String)
        case album(id: String, nameHint: String?)
        case artist(id: String, nameHint: String?)

        var id: String {
            switch self {
            case .home:
                return "library.home"
            case .profile:
                return "library.profile"
            case .likedSongs:
                return "library.likedSongs"
            case .search:
                return "library.search"
            case .playlist(let playlistID):
                return playlistID
            case .album(let albumID, _):
                return "album.\(albumID)"
            case .artist(let artistID, _):
                return "artist.\(artistID)"
            }
        }

        func title(playlists: [SpotifyPlaylistItem]) -> String {
            switch self {
            case .home:
                return "Home"
            case .profile:
                return "Profile"
            case .likedSongs:
                return "Liked Songs"
            case .search:
                return "Search"
            case .playlist(let playlistID):
                return playlists.first(where: { $0.id == playlistID })?.name ?? "Playlist"
            case .album(_, let nameHint):
                return nameHint ?? "Album"
            case .artist(_, let nameHint):
                return nameHint ?? "Artist"
            }
        }
    }

    var phase: Phase = .bootstrapping
    var authError: String?
    var loadError: String?

    /// True when `GET /playlists/{id}/items` returned 403; Web Playback can still play the playlist context.
    private(set) var isPlaylistTrackListForbidden: Bool = false

    /// Shown in the playlist detail body (below the hero), not as the global red banner.
    static let playlistTracksUnavailableMessage =
        "Sorry, but we can only show playlists you own. You can still play the playlist."

    /// Saved tracks (`GET /me/tracks`), windowed in memory for Home and the Liked Songs list.
    private(set) var likedSongs: [SpotifyTrack] = []

    /// Full ordered id list for the user’s saved library; much cheaper to keep than every full track payload.
    private(set) var likedSongIDsInOrder: [String] = []

    /// Total count reported by Spotify even when only the first page is loaded.
    private(set) var likedSongsTotalCount: Int = 0

    /// IDs of saved tracks; updated whenever `likedSongs` changes (O(1) heart state).
    private(set) var likedTrackIDs: Set<String> = []

    /// True while appending the next saved-tracks page for the Liked Songs list.
    private(set) var isLoadingMoreLikedSongs: Bool = false

    private var nextLikedSongsOffset: Int?

    /// Prevents duplicate toggles while a save/remove request is in flight.
    private var likingTrackIDs: Set<String> = []
    /// Recent playback history (`GET /me/player/recently-played`), shown on Home.
    private(set) var recentlyPlayed: [SpotifyRecentPlayRow] = []
    private(set) var playlists: [SpotifyPlaylistItem] = []
    /// Cached `GET /playlists/{id}/tracks` results.
    private var playlistTracksCache: [String: [SpotifyTrack]] = [:]
    private var playlistTrackCacheOrder: [String] = []

    /// Cached `GET /albums/{id}/tracks` results.
    private var albumTracksCache: [String: [SpotifyTrack]] = [:]
    private var albumTrackCacheOrder: [String] = []

    /// Album header metadata from `GET /albums/{id}` or seeded from search / track payloads.
    private var albumMetadataByID: [String: SpotifyAlbum] = [:]

    /// Playlist metadata when the user opens a playlist from search (or other flows) before it appears in `/me/playlists`.
    private var playlistMetadataByID: [String: SpotifyPlaylistItem] = [:]

    /// Playlists the current user can likely edit via the Web API (owner, or collaborative playlist).
    var modifiablePlaylists: [SpotifyPlaylistItem] {
        playlists.filter {
            !$0.isLikelyLikedSongsMirror &&
                $0.isLikelyEditableByCurrentUser(currentUserId: currentSpotifyUserId)
        }
    }

    /// Sheet: create playlist (from sidebar or from track “+” → New Playlist).
    var isNewPlaylistSheetPresented: Bool = false
    /// When non-nil, the new playlist will include this track after creation.
    var pendingTrackForNewPlaylist: SpotifyTrack?
    var isCreatingPlaylist: Bool = false
    /// User-facing error for playlist create / add flows (shown in sheets and transiently elsewhere).
    var playlistActionError: String?
    var isMutatingSelectedPlaylist: Bool = false

    private var ongoingPlaylistAddKeys: Set<String> = []
    private var ongoingPlaylistRemoveKeys: Set<String> = []
    /// Last non-album library selection so album detail can offer a contextual Back action.
    private var albumBackSelection: LibrarySelection?

    /// `market` for playlist endpoints ([Get Playlist Items](https://developer.spotify.com/documentation/web-api/reference/get-playlists-items)); ISO 3166-1 alpha-2 from `GET /v1/me` when available.
    private var playlistMarketForAPI: String {
        Self.normalizedMarketCode(currentUserProfile?.country)
    }

    var selectedLibrary: LibrarySelection = .home
    /// True while fetching tracks for a playlist that isn’t cached yet.
    private(set) var isLoadingPlaylistTracks: Bool = false

    /// True while fetching tracks for an album that isn’t cached yet.
    private(set) var isLoadingAlbumTracks: Bool = false

    /// Non-fatal notes when album header or track list partially fails (403 on one call, etc.).
    private(set) var albumCatalogWarning: String?

    func acknowledgeAlbumCatalogWarning() {
        albumCatalogWarning = nil
    }

    /// Bound to the Search screen query field; not used for API until the user runs a search.
    var searchQueryText: String = ""

    /// Tab filter on the Search screen (`All` shows a compact overview).
    enum SearchTab: String, CaseIterable, Identifiable, Hashable {
        case all
        case songs
        case artists
        case albums
        case playlists

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "All"
            case .songs: return "Songs"
            case .artists: return "Artists"
            case .albums: return "Albums"
            case .playlists: return "Playlists"
            }
        }
    }

    var selectedSearchTab: SearchTab = .all

    /// Catalog multi-type search (`GET /v1/search`); independent from library caches.
    private(set) var catalogSearch: SpotifyCatalogSearchSnapshot = .init(
        tracks: [],
        artists: [],
        albums: [],
        playlists: []
    )
    private(set) var isSearching: Bool = false
    var searchError: String?

    private var storedSession: StoredSpotifySession?
    private let authService = SpotifyAuthService()
    private let api = SpotifyAPIClient()

    private static let initialLikedSongsPageSize = 50
    private static let likedSongsPrefetchThreshold = 8
    private static let maxPlaylistTrackCacheEntries = 8
    private static let maxAlbumTrackCacheEntries = 8

    /// Tracks shown in the main section for the current selection.
    var tracksForSelectedLibrary: [SpotifyTrack] {
        switch selectedLibrary {
        case .home, .profile, .search, .artist:
            return []
        case .likedSongs:
            return likedSongs
        case .playlist(let playlistID):
            return playlistTracksCache[playlistID] ?? []
        case .album(let albumID, _):
            return albumTracksCache[albumID] ?? []
        }
    }

    /// Library playlist entry wins over search-only cached metadata.
    func resolvedPlaylist(id: String) -> SpotifyPlaylistItem? {
        playlists.first(where: { $0.id == id }) ?? playlistMetadataByID[id]
    }

    /// Whether the user can likely remove tracks via the Web API (owner or collaborator on a non–Liked-Songs mirror playlist).
    func canEditPlaylist(id: String) -> Bool {
        guard let pl = resolvedPlaylist(id: id) else { return false }
        return !pl.isLikelyLikedSongsMirror
            && pl.isLikelyEditableByCurrentUser(currentUserId: currentSpotifyUserId)
    }

    /// Navigation bar title for the detail column, including playlist names from search.
    var detailNavigationTitle: String {
        switch selectedLibrary {
        case .playlist(let playlistID):
            return resolvedPlaylist(id: playlistID)?.name ?? "Playlist"
        case .album(let albumID, let hint):
            return albumMetadataByID[albumID]?.name ?? hint ?? "Album"
        default:
            return selectedLibrary.title(playlists: playlists)
        }
    }

    /// Album header for the current selection when it is an album.
    func resolvedAlbum(id: String) -> SpotifyAlbum? {
        albumMetadataByID[id]
    }

    var isShowingAlbumDetail: Bool {
        if case .album = selectedLibrary { return true }
        return false
    }

    var canGoBackFromAlbum: Bool {
        isShowingAlbumDetail && albumBackSelection != nil
    }

    /// Open a playlist in the main detail area (e.g. from search). Seeds metadata when the playlist isn’t in `/me/playlists` yet.
    func openPlaylist(_ playlist: SpotifyPlaylistItem) async {
        if playlists.contains(where: { $0.id == playlist.id }) {
            playlistMetadataByID.removeValue(forKey: playlist.id)
        } else {
            playlistMetadataByID[playlist.id] = playlist
        }
        await selectLibrary(.playlist(id: playlist.id))
    }

    /// Opens album detail; optionally seeds hero metadata (e.g. from search) before network loads complete.
    func openAlbum(id albumID: String, nameHint: String?, seedAlbum: SpotifyAlbum? = nil) async {
        let trimmed = albumID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        loadError = nil
        if case .album = selectedLibrary {
            // Preserve the original non-album source while browsing between albums.
        } else {
            albumBackSelection = selectedLibrary
        }
        if let seed = seedAlbum {
            albumMetadataByID[trimmed] = seed
        }
        await selectLibrary(.album(id: trimmed, nameHint: nameHint ?? seedAlbum?.name))
    }

    func openAlbumFromSearch(_ album: SpotifySearchAlbumItem) async {
        await openAlbum(id: album.id, nameHint: album.name, seedAlbum: SpotifyAlbum(fromSearchItem: album))
    }

    /// Resolves album from track `album.id`, or fetches `GET /tracks/{id}` when missing (e.g. some Web Playback payloads).
    func openAlbum(from track: SpotifyTrack) async {
        if let aid = track.albumId, !aid.isEmpty {
            await openAlbum(id: aid, nameHint: track.album?.name, seedAlbum: track.album)
            return
        }
        guard !track.id.isEmpty else { return }
        do {
            try await withFreshAccessToken { token in
                let full = try await self.api.fetchTrack(accessToken: token, id: track.id)
                if let aid = full.albumId, !aid.isEmpty {
                    await self.openAlbum(id: aid, nameHint: full.album?.name, seedAlbum: full.album)
                } else {
                    self.loadError = "Couldn’t find this album in Spotify’s catalog for this track."
                }
            }
        } catch AppSessionError.sessionExpired {
            loadError = "Session expired. Please sign in again."
            signOut()
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Opens the album for the current Web Playback state (album context or track’s album via REST).
    func openAlbumFromPlaybackState(
        contextURI: String?,
        trackURI: String?,
        albumNameHint: String?
    ) async {
        loadError = nil
        if let ctx = contextURI, ctx.hasPrefix("spotify:album:") {
            let id = String(ctx.dropFirst("spotify:album:".count))
            await openAlbum(id: id, nameHint: albumNameHint)
            return
        }
        guard let uri = trackURI, uri.hasPrefix("spotify:track:") else {
            loadError = "Album isn’t available for this playback state yet."
            return
        }
        let tid = String(uri.dropFirst("spotify:track:".count))
        guard !tid.isEmpty else { return }
        do {
            try await withFreshAccessToken { token in
                let track = try await self.api.fetchTrack(accessToken: token, id: tid)
                await self.openAlbum(from: track)
            }
        } catch AppSessionError.sessionExpired {
            loadError = "Session expired. Please sign in again."
            signOut()
        } catch {
            loadError = error.localizedDescription
        }
    }

    func goBackFromAlbum() async {
        guard case .album = selectedLibrary else { return }
        let target = albumBackSelection ?? .home
        albumBackSelection = nil
        await selectLibrary(target)
    }

    func bootstrap() async {
        // `ContentView`’s `.task` runs again when the main window reopens (e.g. after mini player).
        // Session + caches already live in memory — avoid resetting to loading / refetching library.
        if phase == .ready {
            return
        }

        phase = .bootstrapping

        do {
            if var session = try SpotifyTokenStore.load() {
                if !session.includesRequiredScopes() {
                    SpotifyTokenStore.clear()
                    storedSession = nil
                    authError = "Sign in again to grant the latest Spotify permissions for library playback."
                    phase = .needsLogin
                    return
                }
                session = try await refreshIfNeeded(session)
                try SpotifyTokenStore.save(session)
                storedSession = session
                phase = .loadingContent
                await loadLibrary(session: session)
            } else {
                phase = .needsLogin
            }
        } catch {
            authError = error.localizedDescription
            SpotifyTokenStore.clear()
            phase = .needsLogin
        }
    }

    func signIn() async {
        authError = nil
        do {
            let session = try await authService.signIn()
            try SpotifyTokenStore.save(session)
            storedSession = session
            phase = .loadingContent
            await loadLibrary(session: session)
        } catch let error as SpotifyAuthError {
            if case .cancelled = error { return }
            authError = error.localizedDescription
            phase = .needsLogin
        } catch {
            authError = error.localizedDescription
            phase = .needsLogin
        }
    }

    func signOut() {
        SpotifyTokenStore.clear()
        storedSession = nil
        currentUserProfile = nil
        likedSongs = []
        likedSongIDsInOrder = []
        likedSongsTotalCount = 0
        likedTrackIDs = []
        isLoadingMoreLikedSongs = false
        nextLikedSongsOffset = nil
        likingTrackIDs = []
        recentlyPlayed = []
        playlists = []
        playlistTracksCache = [:]
        playlistTrackCacheOrder = []
        playlistMetadataByID = [:]
        albumTracksCache = [:]
        albumTrackCacheOrder = []
        albumMetadataByID = [:]
        albumCatalogWarning = nil
        isLoadingAlbumTracks = false
        albumBackSelection = nil
        isNewPlaylistSheetPresented = false
        pendingTrackForNewPlaylist = nil
        isCreatingPlaylist = false
        playlistActionError = nil
        isMutatingSelectedPlaylist = false
        ongoingPlaylistAddKeys = []
        selectedLibrary = .home
        phase = .needsLogin
        loadError = nil
        isPlaylistTrackListForbidden = false
        clearSearchState()
    }

    func reloadLibrary() async {
        guard let session = storedSession else { return }
        authError = nil
        loadError = nil
        isPlaylistTrackListForbidden = false
        phase = .loadingContent
        await loadLibrary(session: session)
    }

    /// Call when the user picks a sidebar row. Loads playlist or album tracks on demand.
    func selectLibrary(_ selection: LibrarySelection) async {
        selectedLibrary = selection
        if selection != .search {
            searchError = nil
        }
        if case .playlist = selection {} else {
            isPlaylistTrackListForbidden = false
        }
        albumCatalogWarning = nil

        switch selection {
        case .likedSongs:
            await loadMoreLikedSongsIfNeeded()

        case .playlist(let playlistID):
            if let idx = playlists.firstIndex(where: { $0.id == playlistID }),
               playlists[idx].images?.isEmpty ?? true
            {
                await fetchPlaylistCoverIfNeeded(playlistID: playlistID, index: idx)
            }

            if playlistTracksCache[playlistID] != nil {
                touchPlaylistTrackCacheEntry(playlistID)
                return
            }

            isLoadingPlaylistTracks = true
            loadError = nil
            isPlaylistTrackListForbidden = false
            defer { isLoadingPlaylistTracks = false }

            do {
                try await withFreshAccessToken { token in
                    let tracks = try await self.api.fetchAllPlaylistTracks(
                        accessToken: token,
                        playlistID: playlistID,
                        market: self.playlistMarketForAPI
                    )
                    self.cachePlaylistTracks(tracks, for: playlistID)
                }
            } catch AppSessionError.sessionExpired {
                loadError = "Session expired. Please sign in again."
                signOut()
            } catch let apiErr as SpotifyAPIError {
                if case .http(403, _) = apiErr {
                    isPlaylistTrackListForbidden = true
                } else {
                    loadError = apiErr.localizedDescription
                }
            } catch {
                loadError = error.localizedDescription
            }

        case .album(let albumID, _):
            await loadAlbumTracksIfNeeded(albumID: albumID)

        default:
            break
        }
    }

    /// Loads album metadata and tracks (partial success allowed, like `loadArtistCatalog`).
    private func loadAlbumTracksIfNeeded(albumID: String) async {
        if albumTracksCache[albumID] != nil {
            touchAlbumTrackCacheEntry(albumID)
            await refreshAlbumMetadataIfNeeded(albumID: albumID)
            return
        }

        isLoadingAlbumTracks = true
        loadError = nil
        defer { isLoadingAlbumTracks = false }

        let market = playlistMarketForAPI

        let fetchParts: (String) async throws -> (SpotifyAlbum?, [SpotifyTrack], String?) = { token in
            var meta: SpotifyAlbum?
            var tracks: [SpotifyTrack] = []
            var notes: [String] = []

            do {
                meta = try await self.api.fetchAlbum(accessToken: token, albumID: albumID, market: market)
            } catch let apiErr as SpotifyAPIError {
                if case .http(401, _) = apiErr { throw apiErr }
                notes.append(self.catalogFailureMessage(apiErr, context: "album details"))
            } catch {
                notes.append(error.localizedDescription)
            }

            do {
                tracks = try await self.api.fetchAllAlbumTracks(
                    accessToken: token,
                    albumID: albumID,
                    market: market
                )
            } catch let apiErr as SpotifyAPIError {
                if case .http(401, _) = apiErr { throw apiErr }
                notes.append(self.catalogFailureMessage(apiErr, context: "album tracks"))
            } catch {
                notes.append(error.localizedDescription)
            }

            let albumForTracks = meta ?? self.albumMetadataByID[albumID]
            if let albumForTracks {
                tracks = tracks.map { $0.replacingAlbum(albumForTracks) }
            }

            if let meta {
                self.albumMetadataByID[albumID] = meta
            }
            if !tracks.isEmpty {
                self.cacheAlbumTracks(tracks, for: albumID)
            }

            let warning = notes.isEmpty ? nil : notes.joined(separator: "\n")
            return (meta, tracks, warning)
        }

        do {
            let result = try await withFreshAccessToken { try await fetchParts($0) }
            albumCatalogWarning = result.2
            if result.1.isEmpty, result.0 == nil, albumMetadataByID[albumID] == nil {
                loadError = albumCatalogWarning ?? "Couldn’t load this album."
            }
        } catch AppSessionError.sessionExpired {
            loadError = "Session expired. Please sign in again."
            signOut()
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Fetches `GET /albums/{id}` when the cache has tracks but metadata is missing (e.g. cold open).
    private func refreshAlbumMetadataIfNeeded(albumID: String) async {
        guard albumMetadataByID[albumID] == nil else { return }
        let market = playlistMarketForAPI
        try? await withFreshAccessToken { token in
            let meta = try await self.api.fetchAlbum(accessToken: token, albumID: albumID, market: market)
            self.albumMetadataByID[albumID] = meta
        }
    }

    private func catalogFailureMessage(_ error: SpotifyAPIError, context: String) -> String {
        switch error {
        case let .http(403, body):
            let detail = body.flatMap { $0.isEmpty ? nil : " \($0)" } ?? ""
            return """
            Spotify returned Forbidden (403) for \(context).\(detail)
            This can happen when the Web API blocks an endpoint for your app (quota / development mode — see https://developer.spotify.com/documentation/web-api/concepts/quota-modes). Try signing out and signing in again, or request extended API access if you need full catalog data.
            """
        case .http:
            return "\(context): \(error.localizedDescription)"
        case .decoding:
            return "\(context): \(error.localizedDescription)"
        }
    }

    /// Loads `GET /playlists/{id}/images` when `/me/playlists` omitted artwork.
    private func fetchPlaylistCoverIfNeeded(playlistID: String, index: Int) async {
        try? await withFreshAccessToken { token in
            let imgs = try await self.api.fetchPlaylistCoverImages(accessToken: token, playlistID: playlistID)
            guard !imgs.isEmpty else { return }
            guard self.playlists.indices.contains(index), self.playlists[index].id == playlistID else { return }
            self.playlists[index] = self.playlists[index].replacingImages(imgs)
        }
    }

    /// Runs a Spotify catalog search (tracks, artists, albums, playlists). Empty/whitespace query clears results and errors.
    func searchCatalog(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            catalogSearch = SpotifyCatalogSearchSnapshot(tracks: [], artists: [], albums: [], playlists: [])
            searchError = nil
            isSearching = false
            return
        }

        isSearching = true
        searchError = nil
        defer { isSearching = false }

        do {
            catalogSearch = try await withFreshAccessToken { token in
                try await self.api.searchCatalog(accessToken: token, query: trimmed, limit: 10, offset: 0)
            }
        } catch AppSessionError.sessionExpired {
            searchError = "Session expired. Please sign in again."
            catalogSearch = SpotifyCatalogSearchSnapshot(tracks: [], artists: [], albums: [], playlists: [])
            signOut()
        } catch {
            searchError = error.localizedDescription
            catalogSearch = SpotifyCatalogSearchSnapshot(tracks: [], artists: [], albums: [], playlists: [])
        }
    }

    private func clearSearchState() {
        searchQueryText = ""
        selectedSearchTab = .all
        catalogSearch = SpotifyCatalogSearchSnapshot(tracks: [], artists: [], albums: [], playlists: [])
        searchError = nil
        isSearching = false
    }

    private func refreshIfNeeded(_ session: StoredSpotifySession) async throws -> StoredSpotifySession {
        if session.accessTokenExpiry > Date().addingTimeInterval(30) {
            return session
        }
        return try await authService.refreshSession(session)
    }

    private func loadLibrary(session: StoredSpotifySession) async {
        loadError = nil
        isPlaylistTrackListForbidden = false
        playlistTracksCache = [:]
        playlistTrackCacheOrder = []
        playlistMetadataByID = [:]
        albumTracksCache = [:]
        albumTrackCacheOrder = []
        albumMetadataByID = [:]
        albumCatalogWarning = nil
        isLoadingAlbumTracks = false
        isLoadingMoreLikedSongs = false
        nextLikedSongsOffset = nil
        albumBackSelection = nil
        clearSearchState()
        selectedLibrary = .home
        do {
            let access = session.accessToken
            if let me = try? await api.fetchCurrentUser(accessToken: access) {
                currentUserProfile = me
            } else {
                currentUserProfile = nil
            }

            async let playlistsTask = api.fetchUserPlaylists(accessToken: access, limit: 50)
            async let likedPageTask = api.fetchSavedTracksPage(
                accessToken: access,
                limit: Self.initialLikedSongsPageSize,
                offset: 0
            )
            async let likedIDsTask = api.fetchAllSavedTrackIDs(accessToken: access)

            playlists = try await playlistsTask
            let likedPage = try await likedPageTask
            applyLikedSongsPage(likedPage, replaceExisting: true)
            do {
                let likedIDs = try await likedIDsTask
                applyLikedSongIDs(likedIDs, totalHint: likedPage.total)
            } catch {
                applyLikedSongIDs(likedSongs.map(\.id), totalHint: likedPage.total)
            }

            do {
                let items = try await api.fetchRecentlyPlayed(accessToken: access)
                recentlyPlayed = SpotifyRecentPlayRow.rows(from: items)
            } catch {
                recentlyPlayed = []
            }

            phase = .ready
        } catch let apiErr as SpotifyAPIError {
            if case let .http(code, _) = apiErr, code == 401 {
                do {
                    let refreshed = try await authService.refreshSession(session)
                    try SpotifyTokenStore.save(refreshed)
                    storedSession = refreshed
                    await loadLibrary(session: refreshed)
                } catch {
                    loadError = "Session expired. Please sign in again."
                    signOut()
                }
            } else if case let .http(code, body) = apiErr,
                      code == 403,
                      (body ?? "").localizedCaseInsensitiveContains("insufficient client scope")
            {
                SpotifyTokenStore.clear()
                storedSession = nil
                authError = "Spotify needs you to sign in again to grant library access."
                phase = .needsLogin
            } else {
                loadError = apiErr.localizedDescription
                phase = .ready
            }
        } catch {
            loadError = error.localizedDescription
            phase = .ready
        }
    }

    func isTrackLiked(_ trackID: String) -> Bool {
        likedTrackIDs.contains(trackID)
    }

    var hasMoreLikedSongsToLoad: Bool {
        nextLikedSongsOffset != nil
    }

    func isTogglingLikedTrack(_ trackID: String) -> Bool {
        likingTrackIDs.contains(trackID)
    }

    /// Like or unlike a track via Spotify saved tracks; updates `likedSongs` and `likedTrackIDs` optimistically.
    func toggleLikedStatus(for track: SpotifyTrack) async {
        guard storedSession != nil else { return }
        let id = track.id
        guard !likingTrackIDs.contains(id) else { return }

        let wasLiked = likedTrackIDs.contains(id)
        let snapshotSongs = likedSongs
        let snapshotIDs = likedSongIDsInOrder
        let snapshotLikedIDs = likedTrackIDs
        let snapshotTotal = likedSongsTotalCount

        if wasLiked {
            likedSongs.removeAll { $0.id == id }
            likedSongIDsInOrder.removeAll { $0 == id }
            likedTrackIDs.remove(id)
            likedSongsTotalCount = max(0, likedSongsTotalCount - 1)
        } else {
            if !likedSongs.contains(where: { $0.id == id }) {
                likedSongs.insert(track, at: 0)
            }
            if !likedSongIDsInOrder.contains(id) {
                likedSongIDsInOrder.insert(id, at: 0)
            }
            likedTrackIDs.insert(id)
            likedSongsTotalCount += 1
        }

        likingTrackIDs.insert(id)
        defer { likingTrackIDs.remove(id) }

        let revertOptimisticState = { [self] in
            likedSongs = snapshotSongs
            likedSongIDsInOrder = snapshotIDs
            likedTrackIDs = snapshotLikedIDs
            likedSongsTotalCount = snapshotTotal
        }

        do {
            try await withFreshAccessToken { token in
                if wasLiked {
                    try await self.api.removeSavedTracks(accessToken: token, trackIDs: [id])
                } else {
                    try await self.api.saveTracks(accessToken: token, trackIDs: [id])
                }
            }
        } catch AppSessionError.sessionExpired {
            revertOptimisticState()
            loadError = "Couldn’t update Liked Songs. Try again."
        } catch let apiErr as SpotifyAPIError {
            revertOptimisticState()
            if case .http(403, _) = apiErr {
                authError =
                    "Spotify returned Forbidden (403). Sign out and sign in again so your account grants library save access (scope user-library-modify). Token refresh alone does not add new permissions."
            } else {
                loadError = apiErr.localizedDescription
            }
        } catch {
            revertOptimisticState()
            loadError = error.localizedDescription
        }
    }

    func loadMoreLikedSongsIfNeeded(currentTrackID: String? = nil) async {
        guard !isLoadingMoreLikedSongs else { return }
        guard let offset = nextLikedSongsOffset else { return }

        if let currentTrackID,
           let index = likedSongs.firstIndex(where: { $0.id == currentTrackID })
        {
            let threshold = max(likedSongs.count - Self.likedSongsPrefetchThreshold, 0)
            guard index >= threshold else { return }
        } else if !likedSongs.isEmpty && selectedLibrary != .likedSongs {
            return
        }

        isLoadingMoreLikedSongs = true
        defer { isLoadingMoreLikedSongs = false }

        do {
            let page = try await withFreshAccessToken { token in
                try await self.api.fetchSavedTracksPage(
                    accessToken: token,
                    limit: Self.initialLikedSongsPageSize,
                    offset: offset
                )
            }
            applyLikedSongsPage(page, replaceExisting: false)
        } catch AppSessionError.sessionExpired {
            loadError = "Session expired. Please sign in again."
            signOut()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func applyLikedSongIDs(_ ids: [String], totalHint: Int?) {
        likedSongIDsInOrder = ids
        likedTrackIDs = Set(ids)
        likedSongsTotalCount = max(totalHint ?? 0, ids.count, likedSongs.count)
    }

    private func applyLikedSongsPage(_ page: SpotifySavedTracksPage, replaceExisting: Bool) {
        let pageTracks = page.items.compactMap(\.track)
        if replaceExisting {
            likedSongs = pageTracks
        } else {
            var merged = likedSongs
            for track in pageTracks where !merged.contains(where: { $0.id == track.id }) {
                merged.append(track)
            }
            likedSongs = merged
        }
        likedSongsTotalCount = max(page.total ?? 0, likedSongsTotalCount, likedSongs.count)
        if let next = page.next, !next.isEmpty {
            nextLikedSongsOffset = (page.offset ?? 0) + (page.limit ?? pageTracks.count)
        } else {
            nextLikedSongsOffset = nil
        }
    }

    private func cachePlaylistTracks(_ tracks: [SpotifyTrack], for playlistID: String) {
        playlistTracksCache[playlistID] = tracks
        touchPlaylistTrackCacheEntry(playlistID)
        while playlistTrackCacheOrder.count > Self.maxPlaylistTrackCacheEntries,
              let evictedID = playlistTrackCacheOrder.first
        {
            playlistTrackCacheOrder.removeFirst()
            playlistTracksCache.removeValue(forKey: evictedID)
        }
    }

    private func touchPlaylistTrackCacheEntry(_ playlistID: String) {
        playlistTrackCacheOrder.removeAll { $0 == playlistID }
        playlistTrackCacheOrder.append(playlistID)
    }

    private func cacheAlbumTracks(_ tracks: [SpotifyTrack], for albumID: String) {
        albumTracksCache[albumID] = tracks
        touchAlbumTrackCacheEntry(albumID)
        while albumTrackCacheOrder.count > Self.maxAlbumTrackCacheEntries,
              let evictedID = albumTrackCacheOrder.first
        {
            albumTrackCacheOrder.removeFirst()
            albumTracksCache.removeValue(forKey: evictedID)
        }
    }

    private func touchAlbumTrackCacheEntry(_ albumID: String) {
        albumTrackCacheOrder.removeAll { $0 == albumID }
        albumTrackCacheOrder.append(albumID)
    }

    /// Loads artist profile, top tracks, and optional search/album fallbacks (`GET /artists/{id}`, `/top-tracks`, `/search`, `/albums`).
    /// Suppresses error **alerts** when any section loaded successfully. Only **401** triggers refresh + single retry.
    func loadArtistCatalog(artistID: String, nameHint: String? = nil) async throws -> (SpotifyArtistProfile?, [SpotifyTrack], [SpotifyAlbum], String?) {
        let fetchParts: (String) async throws -> (SpotifyArtistProfile?, [SpotifyTrack], [SpotifyAlbum], String?) = { token in
            if self.currentUserProfile == nil {
                if let me = try? await self.api.fetchCurrentUser(accessToken: token) {
                    self.currentUserProfile = me
                }
            }
            let isoMarket = Self.normalizedMarketCode(self.currentUserProfile?.country)

            var profile: SpotifyArtistProfile?
            var tracks: [SpotifyTrack] = []
            var albums: [SpotifyAlbum] = []
            var notes: [String] = []

            do {
                profile = try await self.api.fetchArtist(accessToken: token, id: artistID)
            } catch let apiErr as SpotifyAPIError {
                if case .http(401, _) = apiErr { throw apiErr }
                notes.append(self.catalogFailureMessage(apiErr, context: "artist profile"))
            } catch {
                notes.append(error.localizedDescription)
            }

            do {
                tracks = try await self.api.fetchArtistTopTracksResolvingMarket(
                    accessToken: token,
                    artistID: artistID,
                    isoMarketFallback: isoMarket
                )
            } catch let apiErr as SpotifyAPIError {
                if case .http(401, _) = apiErr { throw apiErr }
                notes.append(self.catalogFailureMessage(apiErr, context: "top tracks"))
            } catch {
                notes.append(error.localizedDescription)
            }

            let searchName = profile?.name ?? nameHint
            if tracks.isEmpty, let name = searchName, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let found = await self.tracksMatchingArtistForFallback(
                    accessToken: token,
                    artistID: artistID,
                    artistName: name
                )
                if !found.isEmpty {
                    tracks = found
                }
            }

            if tracks.isEmpty {
                do {
                    let items = try await self.api.fetchArtistAlbumsResolvingMarket(
                        accessToken: token,
                        artistID: artistID,
                        isoMarketFallback: isoMarket
                    )
                    var seen = Set<String>()
                    albums = items.filter { album in
                        guard let id = album.id, !id.isEmpty else { return false }
                        if seen.contains(id) { return false }
                        seen.insert(id)
                        return true
                    }
                } catch let apiErr as SpotifyAPIError {
                    if case .http(401, _) = apiErr { throw apiErr }
                } catch {}
            }

            let hasAnything = profile != nil || !tracks.isEmpty || !albums.isEmpty
            let warning: String?
            if hasAnything {
                warning = nil
            } else {
                warning = notes.isEmpty ? "Couldn’t load this artist." : notes.joined(separator: "\n")
            }
            return (profile, tracks, albums, warning)
        }

        return try await withFreshAccessToken { try await fetchParts($0) }
    }

    /// Search-only track results filtered to `artistID` (fallback when top-tracks is empty or forbidden).
    private func tracksMatchingArtistForFallback(
        accessToken: String,
        artistID: String,
        artistName: String
    ) async -> [SpotifyTrack] {
        let trimmed = artistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let safeName = trimmed.replacingOccurrences(of: "\"", with: "")

        do {
            let primaryQuery = "artist:\\\"\(safeName)\\\""
            let primary = try await api.searchTracks(accessToken: accessToken, query: primaryQuery)
            let filtered = primary.filter { track in
                track.artists.contains { ($0.id ?? "") == artistID }
            }
            if !filtered.isEmpty {
                return Array(filtered.prefix(10))
            }

            let loose = try await api.searchTracks(accessToken: accessToken, query: safeName)
            let looseFiltered = loose.filter { track in
                track.artists.contains { ($0.id ?? "") == artistID }
            }
            return Array(looseFiltered.prefix(10))
        } catch {
            return []
        }
    }

    /// ISO market for `market` query fallbacks when `from_token` is rejected (400); also used by album fallback.
    private static func normalizedMarketCode(_ country: String?) -> String {
        let raw = (country ?? "US").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard raw.count == 2, raw.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) }) else {
            return "US"
        }
        return raw
    }

    /// Fresh access token for Web API / Web Playback (refreshes when near expiry).
    func validAccessToken() async throws -> String {
        guard var session = storedSession else {
            throw AppSessionError.notSignedIn
        }
        if session.accessTokenExpiry <= Date().addingTimeInterval(30) {
            session = try await authService.refreshSession(session)
            try SpotifyTokenStore.save(session)
            storedSession = session
        }
        return session.accessToken
    }

    /// Runs `operation` with a fresh access token. On `SpotifyAPIError.http(401, _)` the stored
    /// session is refreshed once and the operation retried. If the refresh itself fails, or the
    /// retry still fails authentication, `AppSessionError.sessionExpired` is thrown so callers
    /// can uniformly force sign-out. All other errors propagate unchanged.
    @discardableResult
    private func withFreshAccessToken<T>(
        _ operation: @MainActor (String) async throws -> T
    ) async throws -> T {
        let access = try await validAccessToken()
        do {
            return try await operation(access)
        } catch let apiErr as SpotifyAPIError {
            guard case .http(401, _) = apiErr, let session = storedSession else {
                throw apiErr
            }
            do {
                let refreshed = try await authService.refreshSession(session)
                try SpotifyTokenStore.save(refreshed)
                storedSession = refreshed
                return try await operation(refreshed.accessToken)
            } catch {
                throw AppSessionError.sessionExpired
            }
        }
    }

    // MARK: - Playlists (create / add)

    func presentNewPlaylistSheet(trackToAddFirst: SpotifyTrack? = nil) {
        playlistActionError = nil
        pendingTrackForNewPlaylist = trackToAddFirst
        isNewPlaylistSheetPresented = true
    }

    func dismissNewPlaylistSheet() {
        isNewPlaylistSheetPresented = false
        pendingTrackForNewPlaylist = nil
        playlistActionError = nil
    }

    func isAddingTrack(_ trackID: String, toPlaylist playlistID: String) -> Bool {
        ongoingPlaylistAddKeys.contains("\(trackID)|\(playlistID)")
    }

    func isRemovingTrack(_ trackID: String, fromPlaylist playlistID: String) -> Bool {
        ongoingPlaylistRemoveKeys.contains("\(trackID)|\(playlistID)")
    }

    /// Creates a playlist, optionally uploads cover art, optionally adds `pendingTrackForNewPlaylist`, then selects the new playlist.
    func createPlaylistFromSheet(
        name: String,
        isPublic: Bool,
        description: String?,
        coverFileURL: URL?
    ) async -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            playlistActionError = "Playlist name can’t be empty."
            return false
        }
        let trimmedDescription = description?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let descOrNil: String? = (trimmedDescription?.isEmpty ?? true) ? nil : trimmedDescription

        guard storedSession != nil else {
            playlistActionError = AppSessionError.notSignedIn.localizedDescription
            return false
        }

        isCreatingPlaylist = true
        playlistActionError = nil
        defer { isCreatingPlaylist = false }

        do {
            let created = try await createPlaylistWithRetry(
                name: trimmedName,
                isPublic: isPublic,
                description: descOrNil
            )

            if let coverURL = coverFileURL {
                do {
                    let token = try await validAccessToken()
                    let useAccess = coverURL.startAccessingSecurityScopedResource()
                    defer {
                        if useAccess { coverURL.stopAccessingSecurityScopedResource() }
                    }
                    let jpeg = try PlaylistCoverEncoding.jpegDataForSpotifyUpload(fromFileURL: coverURL)
                    try await api.uploadPlaylistCoverImage(
                        accessToken: token,
                        playlistID: created.id,
                        jpegData: jpeg
                    )
                    if let imgs = try? await api.fetchPlaylistCoverImages(accessToken: token, playlistID: created.id),
                       !imgs.isEmpty
                    {
                        upsertPlaylistInList(created.replacingImages(imgs))
                    } else {
                        upsertPlaylistInList(created)
                    }
                } catch {
                    playlistActionError =
                        "Playlist created, but the cover couldn’t be uploaded: \(error.localizedDescription)"
                    upsertPlaylistInList(created)
                }
            } else {
                upsertPlaylistInList(created)
            }

            guard let finalPl = playlists.first(where: { $0.id == created.id }) else {
                playlistActionError = "Playlist was created but couldn’t be shown. Try Refresh."
                return false
            }

            let pending = pendingTrackForNewPlaylist
            pendingTrackForNewPlaylist = nil

            if let track = pending {
                do {
                    let token = try await validAccessToken()
                    _ = try await api.addItemsToPlaylist(
                        accessToken: token,
                        playlistID: finalPl.id,
                        trackURIs: ["spotify:track:\(track.id)"]
                    )
                    if let full = try? await api.fetchTrack(accessToken: token, id: track.id) {
                        cachePlaylistTracks([full], for: finalPl.id)
                    }
                } catch {
                    let msg = "Couldn’t add the track to the new playlist: \(error.localizedDescription)"
                    if let existing = playlistActionError, !existing.isEmpty {
                        playlistActionError = existing + "\n" + msg
                    } else {
                        playlistActionError = msg
                    }
                }
            }

            isNewPlaylistSheetPresented = false
            await selectLibrary(.playlist(id: finalPl.id))
            return true
        } catch let apiErr as SpotifyAPIError {
            playlistActionError = playlistMutationErrorMessage(apiErr)
            return false
        } catch {
            playlistActionError = error.localizedDescription
            return false
        }
    }

    private func upsertPlaylistInList(_ playlist: SpotifyPlaylistItem) {
        playlists.removeAll { $0.id == playlist.id }
        playlists.insert(playlist, at: 0)
    }

    private func createPlaylistWithRetry(
        name: String,
        isPublic: Bool,
        description: String?
    ) async throws -> SpotifyPlaylistItem {
        try await withFreshAccessToken { token in
            try await self.api.createPlaylist(
                accessToken: token,
                name: name,
                isPublic: isPublic,
                description: description
            )
        }
    }

    private func playlistMutationErrorMessage(_ err: SpotifyAPIError) -> String {
        switch err {
        case let .http(code, body):
            if code == 403,
               (body ?? "").localizedCaseInsensitiveContains("scope")
            {
                return "Spotify denied playlist changes. Sign out and sign in again to grant playlist edit permissions."
            }
            return err.localizedDescription
        case .decoding:
            return err.localizedDescription
        }
    }

    func renamePlaylist(id playlistID: String, newName: String) async -> Bool {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            playlistActionError = "Playlist name can’t be empty."
            return false
        }
        guard storedSession != nil else {
            playlistActionError = AppSessionError.notSignedIn.localizedDescription
            return false
        }

        isMutatingSelectedPlaylist = true
        playlistActionError = nil
        defer { isMutatingSelectedPlaylist = false }

        do {
            try await renamePlaylistWithRetry(id: playlistID, newName: trimmedName)
            if let index = playlists.firstIndex(where: { $0.id == playlistID }) {
                playlists[index] = playlists[index].replacingMetadata(name: trimmedName)
            }
            if let meta = playlistMetadataByID[playlistID] {
                playlistMetadataByID[playlistID] = meta.replacingMetadata(name: trimmedName)
            }
            return true
        } catch let apiErr as SpotifyAPIError {
            playlistActionError = playlistMutationErrorMessage(apiErr)
            return false
        } catch {
            playlistActionError = error.localizedDescription
            return false
        }
    }

    func deletePlaylist(id playlistID: String) async -> Bool {
        guard storedSession != nil else {
            playlistActionError = AppSessionError.notSignedIn.localizedDescription
            return false
        }

        isMutatingSelectedPlaylist = true
        playlistActionError = nil
        defer { isMutatingSelectedPlaylist = false }

        do {
            try await deletePlaylistWithRetry(id: playlistID)
            playlists.removeAll { $0.id == playlistID }
            playlistTracksCache[playlistID] = nil
            playlistTrackCacheOrder.removeAll { $0 == playlistID }
            playlistMetadataByID.removeValue(forKey: playlistID)
            if case .playlist(let selectedID) = selectedLibrary, selectedID == playlistID {
                selectedLibrary = .home
                loadError = nil
                isPlaylistTrackListForbidden = false
            }
            return true
        } catch let apiErr as SpotifyAPIError {
            playlistActionError = playlistMutationErrorMessage(apiErr)
            return false
        } catch {
            playlistActionError = error.localizedDescription
            return false
        }
    }

    private func renamePlaylistWithRetry(id playlistID: String, newName: String) async throws {
        try await withFreshAccessToken { token in
            try await self.api.renamePlaylist(accessToken: token, playlistID: playlistID, name: newName)
        }
    }

    private func deletePlaylistWithRetry(id playlistID: String) async throws {
        try await withFreshAccessToken { token in
            try await self.api.deletePlaylist(accessToken: token, playlistID: playlistID)
        }
    }

    /// Adds a single track URI to a playlist and updates the cache when this playlist is already loaded.
    func addTrackToPlaylist(trackID: String, playlistID: String) async throws {
        let key = "\(trackID)|\(playlistID)"
        guard storedSession != nil else {
            playlistActionError = AppSessionError.notSignedIn.localizedDescription
            throw AppSessionError.notSignedIn
        }
        guard !ongoingPlaylistAddKeys.contains(key) else { return }
        ongoingPlaylistAddKeys.insert(key)
        defer { ongoingPlaylistAddKeys.remove(key) }
        playlistActionError = nil

        do {
            try await withFreshAccessToken { token in
                _ = try await self.api.addItemsToPlaylist(
                    accessToken: token,
                    playlistID: playlistID,
                    trackURIs: ["spotify:track:\(trackID)"]
                )
                let fullTrack = try await self.api.fetchTrack(accessToken: token, id: trackID)
                if var existing = self.playlistTracksCache[playlistID] {
                    if !existing.contains(where: { $0.id == trackID }) {
                        existing.append(fullTrack)
                        self.cachePlaylistTracks(existing, for: playlistID)
                    }
                }
            }
        } catch AppSessionError.sessionExpired {
            playlistActionError = AppSessionError.sessionExpired.localizedDescription
            throw AppSessionError.sessionExpired
        } catch let apiErr as SpotifyAPIError {
            playlistActionError = playlistMutationErrorMessage(apiErr)
            throw apiErr
        } catch {
            playlistActionError = error.localizedDescription
            throw error
        }
    }

    /// Removes a track URI from a playlist (all occurrences, matching Spotify) and updates the in-memory track list with animation when this playlist is cached.
    func removeTrackFromPlaylist(trackID: String, playlistID: String) async {
        let key = "\(trackID)|\(playlistID)"
        guard storedSession != nil else {
            playlistActionError = AppSessionError.notSignedIn.localizedDescription
            return
        }
        guard !ongoingPlaylistRemoveKeys.contains(key) else { return }
        ongoingPlaylistRemoveKeys.insert(key)
        defer { ongoingPlaylistRemoveKeys.remove(key) }
        playlistActionError = nil

        do {
            try await withFreshAccessToken { token in
                try await self.api.removeItemsFromPlaylist(
                    accessToken: token,
                    playlistID: playlistID,
                    trackURIs: ["spotify:track:\(trackID)"]
                )
            }
            withAnimation(.snappy(duration: 0.32)) {
                if var existing = self.playlistTracksCache[playlistID] {
                    existing.removeAll { $0.id == trackID }
                    self.cachePlaylistTracks(existing, for: playlistID)
                }
            }
        } catch AppSessionError.sessionExpired {
            playlistActionError = AppSessionError.sessionExpired.localizedDescription
        } catch let apiErr as SpotifyAPIError {
            playlistActionError = playlistMutationErrorMessage(apiErr)
        } catch {
            playlistActionError = error.localizedDescription
        }
    }
}

enum AppSessionError: LocalizedError {
    case notSignedIn
    case sessionExpired

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Not signed in to Spotify."
        case .sessionExpired:
            return "Session expired. Please sign in again."
        }
    }
}
