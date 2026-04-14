//
//  AppSession.swift
//  Lightify
//

import Foundation
import Observation

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

    /// Sidebar + detail: Home overview, Liked Songs (saved tracks), catalog search, a user playlist, or an artist detail screen.
    enum LibrarySelection: Equatable, Hashable, Identifiable {
        case home
        case profile
        case likedSongs
        case search
        case playlist(id: String)
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

    /// Saved tracks (`GET /me/tracks`), used for the Home carousel and for the list when Liked Songs is selected.
    private(set) var likedSongs: [SpotifyTrack] = [] {
        didSet { likedTrackIDs = Set(likedSongs.map(\.id)) }
    }

    /// IDs of saved tracks; updated whenever `likedSongs` changes (O(1) heart state).
    private(set) var likedTrackIDs: Set<String> = []

    /// Prevents duplicate toggles while a save/remove request is in flight.
    private var likingTrackIDs: Set<String> = []
    /// Recent playback history (`GET /me/player/recently-played`), shown on Home.
    private(set) var recentlyPlayed: [SpotifyRecentPlayRow] = []
    private(set) var playlists: [SpotifyPlaylistItem] = []
    /// Cached `GET /playlists/{id}/tracks` results.
    private var playlistTracksCache: [String: [SpotifyTrack]] = [:]

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

    /// `market` for playlist endpoints ([Get Playlist Items](https://developer.spotify.com/documentation/web-api/reference/get-playlists-items)); ISO 3166-1 alpha-2 from `GET /v1/me` when available.
    private var playlistMarketForAPI: String {
        Self.normalizedMarketCode(currentUserProfile?.country)
    }

    var selectedLibrary: LibrarySelection = .home
    /// True while fetching tracks for a playlist that isn’t cached yet.
    private(set) var isLoadingPlaylistTracks: Bool = false

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

    /// Tracks shown in the main section for the current selection.
    var tracksForSelectedLibrary: [SpotifyTrack] {
        switch selectedLibrary {
        case .home, .profile, .search, .artist:
            return []
        case .likedSongs:
            return likedSongs
        case .playlist(let playlistID):
            return playlistTracksCache[playlistID] ?? []
        }
    }

    /// Library playlist entry wins over search-only cached metadata.
    func resolvedPlaylist(id: String) -> SpotifyPlaylistItem? {
        playlists.first(where: { $0.id == id }) ?? playlistMetadataByID[id]
    }

    /// Navigation bar title for the detail column, including playlist names from search.
    var detailNavigationTitle: String {
        switch selectedLibrary {
        case .playlist(let playlistID):
            return resolvedPlaylist(id: playlistID)?.name ?? "Playlist"
        default:
            return selectedLibrary.title(playlists: playlists)
        }
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

    func bootstrap() async {
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
        likingTrackIDs = []
        recentlyPlayed = []
        playlists = []
        playlistTracksCache = [:]
        playlistMetadataByID = [:]
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

    /// Call when the user picks a sidebar row. Loads playlist tracks on demand.
    func selectLibrary(_ selection: LibrarySelection) async {
        selectedLibrary = selection
        if selection != .search {
            searchError = nil
        }
        if case .playlist = selection {} else {
            isPlaylistTrackListForbidden = false
        }
        guard case .playlist(let playlistID) = selection else { return }

        if let idx = playlists.firstIndex(where: { $0.id == playlistID }),
           playlists[idx].images?.isEmpty ?? true
        {
            await fetchPlaylistCoverIfNeeded(playlistID: playlistID, index: idx)
        }

        if playlistTracksCache[playlistID] != nil { return }

        isLoadingPlaylistTracks = true
        loadError = nil
        isPlaylistTrackListForbidden = false
        defer { isLoadingPlaylistTracks = false }

        do {
            let access = try await validAccessToken()
            let tracks = try await api.fetchAllPlaylistTracks(
                accessToken: access,
                playlistID: playlistID,
                market: playlistMarketForAPI
            )
            playlistTracksCache[playlistID] = tracks
        } catch let apiErr as SpotifyAPIError {
            if case let .http(code, _) = apiErr, code == 401, let session = storedSession {
                do {
                    let refreshed = try await authService.refreshSession(session)
                    try SpotifyTokenStore.save(refreshed)
                    storedSession = refreshed
                    let tracks = try await api.fetchAllPlaylistTracks(
                        accessToken: refreshed.accessToken,
                        playlistID: playlistID,
                        market: playlistMarketForAPI
                    )
                    playlistTracksCache[playlistID] = tracks
                } catch {
                    loadError = "Session expired. Please sign in again."
                    signOut()
                }
            } else if case let .http(code, _) = apiErr, code == 403 {
                isPlaylistTrackListForbidden = true
            } else {
                loadError = apiErr.localizedDescription
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Loads `GET /playlists/{id}/images` when `/me/playlists` omitted artwork.
    private func fetchPlaylistCoverIfNeeded(playlistID: String, index: Int) async {
        do {
            let access = try await validAccessToken()
            let imgs = try await api.fetchPlaylistCoverImages(accessToken: access, playlistID: playlistID)
            guard !imgs.isEmpty else { return }
            guard playlists.indices.contains(index), playlists[index].id == playlistID else { return }
            playlists[index] = playlists[index].replacingImages(imgs)
        } catch let apiErr as SpotifyAPIError {
            if case let .http(code, _) = apiErr, code == 401, let session = storedSession {
                do {
                    let refreshed = try await authService.refreshSession(session)
                    try SpotifyTokenStore.save(refreshed)
                    storedSession = refreshed
                    let imgs = try await api.fetchPlaylistCoverImages(
                        accessToken: refreshed.accessToken,
                        playlistID: playlistID
                    )
                    guard !imgs.isEmpty else { return }
                    guard playlists.indices.contains(index), playlists[index].id == playlistID else { return }
                    playlists[index] = playlists[index].replacingImages(imgs)
                } catch {}
            }
        } catch {}
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
            let access = try await validAccessToken()
            catalogSearch = try await api.searchCatalog(accessToken: access, query: trimmed, limit: 10, offset: 0)
        } catch let apiErr as SpotifyAPIError {
            if case let .http(code, _) = apiErr, code == 401, let session = storedSession {
                do {
                    let refreshed = try await authService.refreshSession(session)
                    try SpotifyTokenStore.save(refreshed)
                    storedSession = refreshed
                    catalogSearch = try await api.searchCatalog(
                        accessToken: refreshed.accessToken,
                        query: trimmed,
                        limit: 10,
                        offset: 0
                    )
                } catch {
                    searchError = "Session expired. Please sign in again."
                    catalogSearch = SpotifyCatalogSearchSnapshot(tracks: [], artists: [], albums: [], playlists: [])
                    signOut()
                }
            } else {
                searchError = apiErr.localizedDescription
                catalogSearch = SpotifyCatalogSearchSnapshot(tracks: [], artists: [], albums: [], playlists: [])
            }
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
        playlistMetadataByID = [:]
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
            async let likedTask = api.fetchAllSavedTracks(accessToken: access)

            playlists = try await playlistsTask
            likedSongs = try await likedTask

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

    func isTogglingLikedTrack(_ trackID: String) -> Bool {
        likingTrackIDs.contains(trackID)
    }

    /// Like or unlike a track via Spotify saved tracks; updates `likedSongs` and `likedTrackIDs` optimistically.
    func toggleLikedStatus(for track: SpotifyTrack) async {
        guard storedSession != nil else { return }
        let id = track.id
        guard !likingTrackIDs.contains(id) else { return }

        let wasLiked = likedSongs.contains { $0.id == id }
        let snapshotSongs = likedSongs

        if wasLiked {
            likedSongs.removeAll { $0.id == id }
        } else if !likedSongs.contains(where: { $0.id == id }) {
            likedSongs.insert(track, at: 0)
        }

        likingTrackIDs.insert(id)
        defer { likingTrackIDs.remove(id) }

        do {
            let token = try await validAccessToken()
            if wasLiked {
                try await api.removeSavedTracks(accessToken: token, trackIDs: [id])
            } else {
                try await api.saveTracks(accessToken: token, trackIDs: [id])
            }
        } catch let apiErr as SpotifyAPIError {
            if case let .http(code, _) = apiErr, code == 401, let session = storedSession {
                do {
                    let refreshed = try await authService.refreshSession(session)
                    try SpotifyTokenStore.save(refreshed)
                    storedSession = refreshed
                    let token = refreshed.accessToken
                    if wasLiked {
                        try await api.removeSavedTracks(accessToken: token, trackIDs: [id])
                    } else {
                        try await api.saveTracks(accessToken: token, trackIDs: [id])
                    }
                } catch {
                    likedSongs = snapshotSongs
                    loadError = "Couldn’t update Liked Songs. Try again."
                }
            } else if case let .http(code, _) = apiErr, code == 403 {
                likedSongs = snapshotSongs
                authError =
                    "Spotify returned Forbidden (403). Sign out and sign in again so your account grants library save access (scope user-library-modify). Token refresh alone does not add new permissions."
            } else {
                likedSongs = snapshotSongs
                loadError = apiErr.localizedDescription
            }
        } catch {
            likedSongs = snapshotSongs
            loadError = error.localizedDescription
        }
    }

    /// Loads artist profile and top tracks (`GET /artists/{id}` + `/top-tracks`).
    /// Fetches sequentially and **does not fail the whole screen** if one call returns 403 — Spotify can forbid one catalog call while the other succeeds (see [Get Artist](https://developer.spotify.com/documentation/web-api/reference/get-an-artist) / top-tracks responses). Only **401** triggers refresh + single retry.
    func loadArtistCatalog(artistID: String) async throws -> (SpotifyArtistProfile?, [SpotifyTrack], String?) {
        let market = Self.normalizedMarketCode(currentUserProfile?.country)

        let fetchParts: (String) async throws -> (SpotifyArtistProfile?, [SpotifyTrack], String?) = { token in
            var profile: SpotifyArtistProfile?
            var tracks: [SpotifyTrack] = []
            var notes: [String] = []

            do {
                profile = try await self.api.fetchArtist(accessToken: token, id: artistID)
            } catch let apiErr as SpotifyAPIError {
                if case .http(401, _) = apiErr { throw apiErr }
                notes.append(self.artistCatalogFailureMessage(apiErr, context: "artist profile"))
            } catch {
                notes.append(error.localizedDescription)
            }

            do {
                tracks = try await self.api.fetchArtistTopTracks(
                    accessToken: token,
                    artistID: artistID,
                    market: market
                )
            } catch let apiErr as SpotifyAPIError {
                if case .http(401, _) = apiErr { throw apiErr }
                notes.append(self.artistCatalogFailureMessage(apiErr, context: "top tracks"))
            } catch {
                notes.append(error.localizedDescription)
            }

            let warning = notes.isEmpty ? nil : notes.joined(separator: "\n")
            return (profile, tracks, warning)
        }

        do {
            let access = try await validAccessToken()
            return try await fetchParts(access)
        } catch let apiErr as SpotifyAPIError {
            if case .http(401, _) = apiErr, let session = storedSession {
                let refreshed = try await authService.refreshSession(session)
                try SpotifyTokenStore.save(refreshed)
                storedSession = refreshed
                return try await fetchParts(refreshed.accessToken)
            }
            throw apiErr
        }
    }

    private func artistCatalogFailureMessage(_ error: SpotifyAPIError, context: String) -> String {
        switch error {
        case let .http(403, body):
            let detail = body.flatMap { $0.isEmpty ? nil : " \($0)" } ?? ""
            return """
            Spotify returned Forbidden (403) for \(context).\(detail)
            This can happen when the Web API blocks an endpoint for your app (quota / development mode — see https://developer.spotify.com/documentation/web-api/concepts/quota-modes). Try signing out and signing in again, or request extended API access if you need full catalog data. You can still use Play for this artist.
            """
        case .http:
            return "\(context): \(error.localizedDescription)"
        case .decoding:
            return "\(context): \(error.localizedDescription)"
        }
    }

    /// Top-tracks `market` must be ISO 3166-1 alpha-2; invalid values can yield errors from Spotify.
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
                    try await api.addItemsToPlaylist(
                        accessToken: token,
                        playlistID: finalPl.id,
                        trackURIs: ["spotify:track:\(track.id)"]
                    )
                    if let full = try? await api.fetchTrack(accessToken: token, id: track.id) {
                        playlistTracksCache[finalPl.id] = [full]
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
        do {
            let token = try await validAccessToken()
            return try await api.createPlaylist(
                accessToken: token,
                name: name,
                isPublic: isPublic,
                description: description
            )
        } catch let apiErr as SpotifyAPIError {
            if case let .http(code, _) = apiErr, code == 401, let session = storedSession {
                let refreshed = try await authService.refreshSession(session)
                try SpotifyTokenStore.save(refreshed)
                storedSession = refreshed
                return try await api.createPlaylist(
                    accessToken: refreshed.accessToken,
                    name: name,
                    isPublic: isPublic,
                    description: description
                )
            }
            throw apiErr
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
            if var meta = playlistMetadataByID[playlistID] {
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
        do {
            let token = try await validAccessToken()
            try await api.renamePlaylist(accessToken: token, playlistID: playlistID, name: newName)
        } catch let apiErr as SpotifyAPIError {
            if case let .http(code, _) = apiErr, code == 401, let session = storedSession {
                let refreshed = try await authService.refreshSession(session)
                try SpotifyTokenStore.save(refreshed)
                storedSession = refreshed
                try await api.renamePlaylist(accessToken: refreshed.accessToken, playlistID: playlistID, name: newName)
            } else {
                throw apiErr
            }
        }
    }

    private func deletePlaylistWithRetry(id playlistID: String) async throws {
        do {
            let token = try await validAccessToken()
            try await api.deletePlaylist(accessToken: token, playlistID: playlistID)
        } catch let apiErr as SpotifyAPIError {
            if case let .http(code, _) = apiErr, code == 401, let session = storedSession {
                let refreshed = try await authService.refreshSession(session)
                try SpotifyTokenStore.save(refreshed)
                storedSession = refreshed
                try await api.deletePlaylist(accessToken: refreshed.accessToken, playlistID: playlistID)
            } else {
                throw apiErr
            }
        }
    }

    /// Adds a single track URI to a playlist and updates the cache when this playlist is already loaded.
    func addTrackToPlaylist(trackID: String, playlistID: String) async {
        let key = "\(trackID)|\(playlistID)"
        guard storedSession != nil else {
            playlistActionError = AppSessionError.notSignedIn.localizedDescription
            return
        }
        guard !ongoingPlaylistAddKeys.contains(key) else { return }
        ongoingPlaylistAddKeys.insert(key)
        defer { ongoingPlaylistAddKeys.remove(key) }
        playlistActionError = nil

        do {
            let token = try await validAccessToken()
            try await api.addItemsToPlaylist(
                accessToken: token,
                playlistID: playlistID,
                trackURIs: ["spotify:track:\(trackID)"]
            )
            let fullTrack = try await api.fetchTrack(accessToken: token, id: trackID)
            if var existing = playlistTracksCache[playlistID] {
                if !existing.contains(where: { $0.id == trackID }) {
                    existing.append(fullTrack)
                    playlistTracksCache[playlistID] = existing
                }
            }
        } catch let apiErr as SpotifyAPIError {
            if case let .http(code, _) = apiErr, code == 401, let session = storedSession {
                do {
                    let refreshed = try await authService.refreshSession(session)
                    try SpotifyTokenStore.save(refreshed)
                    storedSession = refreshed
                    try await api.addItemsToPlaylist(
                        accessToken: refreshed.accessToken,
                        playlistID: playlistID,
                        trackURIs: ["spotify:track:\(trackID)"]
                    )
                    let fullTrack = try await api.fetchTrack(accessToken: refreshed.accessToken, id: trackID)
                    if var existing = playlistTracksCache[playlistID] {
                        if !existing.contains(where: { $0.id == trackID }) {
                            existing.append(fullTrack)
                            playlistTracksCache[playlistID] = existing
                        }
                    }
                } catch let retryErr as SpotifyAPIError {
                    playlistActionError = playlistMutationErrorMessage(retryErr)
                } catch {
                    playlistActionError = error.localizedDescription
                }
            } else {
                playlistActionError = playlistMutationErrorMessage(apiErr)
            }
        } catch {
            playlistActionError = error.localizedDescription
        }
    }
}

enum AppSessionError: LocalizedError {
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Not signed in to Spotify."
        }
    }
}
