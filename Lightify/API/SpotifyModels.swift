//
//  SpotifyModels.swift
//  Lightify
//

import Foundation

struct SpotifyImage: Codable, Sendable, Identifiable {
    /// May be absent or null for some API payloads; UI should tolerate missing artwork.
    let url: URL?
    let height: Int?
    let width: Int?

    var id: String {
        if let url { return "\(url.absoluteString)-\(width ?? 0)" }
        return "img-\(width ?? 0)-\(height ?? 0)"
    }
}

struct SpotifyArtist: Decodable, Sendable {
    /// Present on simplified artists embedded in tracks; used for navigation to artist screen.
    let id: String?
    let name: String

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case id, name
    }
}

/// Simplified or full album object from track payloads, search, or `GET /v1/albums/{id}`.
/// [SimplifiedAlbumObject](https://developer.spotify.com/documentation/web-api/reference/#object-simplifiedalbumobject)
struct SpotifyAlbum: Decodable, Sendable {
    let id: String?
    let uri: String?
    let name: String
    let images: [SpotifyImage]?
    let artists: [SpotifyArtist]?
    let release_date: String?
    let total_tracks: Int?

    init(
        id: String? = nil,
        uri: String? = nil,
        name: String,
        images: [SpotifyImage]?,
        artists: [SpotifyArtist]? = nil,
        release_date: String? = nil,
        total_tracks: Int? = nil
    ) {
        self.id = id
        self.uri = uri
        self.name = name
        self.images = images
        self.artists = artists
        self.release_date = release_date
        self.total_tracks = total_tracks
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        uri = try c.decodeIfPresent(String.self, forKey: .uri)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        images = try c.decodeIfPresent([SpotifyImage].self, forKey: .images)
        artists = try c.decodeIfPresent([SpotifyArtist].self, forKey: .artists)
        release_date = try c.decodeIfPresent(String.self, forKey: .release_date)
        total_tracks = try c.decodeIfPresent(Int.self, forKey: .total_tracks)
    }

    private enum CodingKeys: String, CodingKey {
        case id, uri, name, images, artists, release_date, total_tracks
    }

    /// Primary line for album hero subtitle (album artists).
    var primaryArtistLine: String {
        artists?.map(\.name).filter { !$0.isEmpty }.joined(separator: ", ") ?? ""
    }

    var largestCoverURL: URL? {
        images?
            .compactMap { img -> (SpotifyImage, URL)? in
                guard let u = img.url else { return nil }
                return (img, u)
            }
            .max(by: { ($0.0.width ?? 0) < ($1.0.width ?? 0) })?
            .1
    }

    /// Best-effort display year from `release_date` (YYYY, YYYY-MM, or YYYY-MM-DD).
    var releaseYearString: String? {
        guard let raw = release_date?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return String(raw.prefix(4))
    }
}

extension SpotifyAlbum {
    /// Seeds album detail UI from a catalog search hit before `GET /albums/{id}` completes.
    init(fromSearchItem item: SpotifySearchAlbumItem) {
        let mappedArtists: [SpotifyArtist]? = item.artists?.map { ref in
            SpotifyArtist(id: ref.id, name: ref.name ?? "")
        }
        self.init(
            id: item.id,
            uri: item.id.isEmpty ? nil : "spotify:album:\(item.id)",
            name: item.name,
            images: item.images,
            artists: mappedArtists,
            release_date: nil,
            total_tracks: nil
        )
    }
}

extension SpotifyArtist {
    init(id: String?, name: String) {
        self.id = id
        self.name = name
    }
}

struct SpotifyTrack: Decodable, Sendable, Identifiable {
    let id: String
    let name: String
    let artists: [SpotifyArtist]
    let album: SpotifyAlbum?
    /// Milliseconds; present on playlist/search track objects from the Web API.
    let duration_ms: Int?

    var primaryArtistName: String {
        artists.map(\.name).joined(separator: ", ")
    }

    /// First credited artist’s Spotify id when unambiguous (single artist on the track).
    var primaryArtistId: String? {
        guard artists.count == 1 else { return nil }
        return artists.first?.id
    }

    /// Spotify album id when present on the nested `album` object (from track / playlist items).
    var albumId: String? {
        album?.id
    }

    var smallImageURL: URL? {
        album?.images?
            .compactMap { img -> (SpotifyImage, URL)? in
                guard let u = img.url else { return nil }
                return (img, u)
            }
            .sorted(by: { ($0.0.width ?? 0) < ($1.0.width ?? 0) })
            .first?.1
    }

    var largestAlbumImageURL: URL? {
        album?.images?
            .compactMap { img -> (SpotifyImage, URL)? in
                guard let u = img.url else { return nil }
                return (img, u)
            }
            .max(by: { ($0.0.width ?? 0) < ($1.0.width ?? 0) })?
            .1
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        artists = try c.decodeIfPresent([SpotifyArtist].self, forKey: .artists) ?? []
        album = try c.decodeIfPresent(SpotifyAlbum.self, forKey: .album)
        duration_ms = try c.decodeIfPresent(Int.self, forKey: .duration_ms)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, artists, album, duration_ms
    }
}

extension SpotifyTrack {
    init(
        id: String,
        name: String,
        artists: [SpotifyArtist],
        album: SpotifyAlbum?,
        duration_ms: Int?
    ) {
        self.id = id
        self.name = name
        self.artists = artists
        self.album = album
        self.duration_ms = duration_ms
    }

    /// Album-track payloads omit nested album art, so detail screens can reattach the parent album.
    func replacingAlbum(_ album: SpotifyAlbum?) -> SpotifyTrack {
        SpotifyTrack(
            id: id,
            name: name,
            artists: artists,
            album: album ?? self.album,
            duration_ms: duration_ms
        )
    }
}

struct SpotifyTracksPage: Decodable, Sendable {
    let items: [SpotifyTrack]
}

/// `GET /v1/me/player/queue` — [Get the user's queue](https://developer.spotify.com/documentation/web-api/reference/get-queue).
struct SpotifyPlayerQueueResponse: Decodable, Sendable {
    let currentlyPlaying: SpotifyTrack?
    let queue: [SpotifyTrack]

    enum CodingKeys: String, CodingKey {
        case currentlyPlaying = "currently_playing"
        case queue
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        queue = (try? c.decode([SpotifyTrack].self, forKey: .queue)) ?? []
        do {
            currentlyPlaying = try c.decodeIfPresent(SpotifyTrack.self, forKey: .currentlyPlaying)
        } catch {
            currentlyPlaying = nil
        }
    }
}

/// `GET /v1/artists/{id}` — [Get Artist](https://developer.spotify.com/documentation/web-api/reference/get-an-artist).
struct SpotifyArtistProfile: Decodable, Sendable, Identifiable {
    let id: String
    let name: String
    let images: [SpotifyImage]?
    let genres: [String]?
    let popularity: Int?
    let followers: SpotifyArtistFollowers?
    let external_urls: SpotifyArtistExternalURLs?

    var largestImageURL: URL? {
        images?
            .compactMap { img -> (SpotifyImage, URL)? in
                guard let u = img.url else { return nil }
                return (img, u)
            }
            .max(by: { ($0.0.width ?? 0) < ($1.0.width ?? 0) })?
            .1
    }

    /// Open in browser / Spotify app.
    var spotifyWebURL: URL? {
        guard let s = external_urls?.spotify, let u = URL(string: s) else { return nil }
        return u
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, images, genres, popularity, followers, external_urls
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        images = try c.decodeIfPresent([SpotifyImage].self, forKey: .images)
        genres = try c.decodeIfPresent([String].self, forKey: .genres)
        popularity = try c.decodeIfPresent(Int.self, forKey: .popularity)
        followers = try c.decodeIfPresent(SpotifyArtistFollowers.self, forKey: .followers)
        external_urls = try c.decodeIfPresent(SpotifyArtistExternalURLs.self, forKey: .external_urls)
    }
}

struct SpotifyArtistFollowers: Decodable, Sendable {
    let total: Int
}

struct SpotifyArtistExternalURLs: Decodable, Sendable {
    let spotify: String?
}

/// `GET /v1/artists/{id}/albums` — paging wrapper for simplified albums.
struct SpotifyArtistAlbumsPage: Decodable, Sendable {
    let items: [SpotifyAlbum]
    let next: String?
}

/// `GET /v1/artists/{id}/top-tracks` — [Get Artist's Top Tracks](https://developer.spotify.com/documentation/web-api/reference/get-an-artists-top-tracks).
struct SpotifyArtistTopTracksResponse: Decodable, Sendable {
    let tracks: [SpotifyTrack]
}

/// `GET /v1/search` — [Search for Item](https://developer.spotify.com/documentation/web-api/reference/search). Response includes one paging object per requested `type`.

/// Artist object returned in search results (includes `id` and images; distinct from nested `SpotifyArtist` on tracks).
struct SpotifySearchArtistItem: Decodable, Sendable, Identifiable {
    let id: String
    let name: String
    let images: [SpotifyImage]?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        images = try c.decodeIfPresent([SpotifyImage].self, forKey: .images)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, images
    }

    var profileImageURL: URL? {
        guard let images, !images.isEmpty else { return nil }
        return images
            .compactMap { img -> (SpotifyImage, URL)? in
                guard let u = img.url else { return nil }
                return (img, u)
            }
            .max(by: { ($0.0.width ?? 0) < ($1.0.width ?? 0) })?
            .1
            ?? images.compactMap(\.url).first
    }
}

struct SpotifySearchAlbumArtistRef: Decodable, Sendable {
    let id: String?
    let name: String?
}

/// Simplified album from search (`albums.items[]`).
struct SpotifySearchAlbumItem: Decodable, Sendable, Identifiable {
    let id: String
    let name: String
    let artists: [SpotifySearchAlbumArtistRef]?
    let images: [SpotifyImage]?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        artists = try c.decodeIfPresent([SpotifySearchAlbumArtistRef].self, forKey: .artists)
        images = try c.decodeIfPresent([SpotifyImage].self, forKey: .images)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, artists, images
    }

    var primaryArtistName: String {
        artists?.compactMap(\.name).joined(separator: ", ") ?? ""
    }

    var coverURL: URL? {
        images?
            .compactMap { img -> (SpotifyImage, URL)? in
                guard let u = img.url else { return nil }
                return (img, u)
            }
            .max(by: { ($0.0.width ?? 0) < ($1.0.width ?? 0) })?
            .1
    }
}

/// Decodes multi-type `GET /v1/search` payloads.
struct SpotifySearchCatalogResponse: Decodable, Sendable {
    struct TracksPaging: Decodable, Sendable {
        let items: [SpotifyTrack]
        let next: String?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let raw = try c.decodeIfPresent([SpotifyTrack?].self, forKey: .items) ?? []
            items = raw.compactMap { $0 }.filter { !$0.id.isEmpty }
            next = try c.decodeIfPresent(String.self, forKey: .next)
        }

        private enum CodingKeys: String, CodingKey {
            case items, next
        }
    }

    struct ArtistsPaging: Decodable, Sendable {
        let items: [SpotifySearchArtistItem]
        let next: String?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let raw = try c.decodeIfPresent([SpotifySearchArtistItem?].self, forKey: .items) ?? []
            items = raw.compactMap { $0 }.filter { !$0.id.isEmpty }
            next = try c.decodeIfPresent(String.self, forKey: .next)
        }

        private enum CodingKeys: String, CodingKey {
            case items, next
        }
    }

    struct AlbumsPaging: Decodable, Sendable {
        let items: [SpotifySearchAlbumItem]
        let next: String?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let raw = try c.decodeIfPresent([SpotifySearchAlbumItem?].self, forKey: .items) ?? []
            items = raw.compactMap { $0 }.filter { !$0.id.isEmpty }
            next = try c.decodeIfPresent(String.self, forKey: .next)
        }

        private enum CodingKeys: String, CodingKey {
            case items, next
        }
    }

    struct PlaylistsPaging: Decodable, Sendable {
        let items: [SpotifyPlaylistItem]
        let next: String?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let raw = try c.decodeIfPresent([SpotifyPlaylistItem?].self, forKey: .items) ?? []
            items = raw.compactMap { $0 }.filter { !$0.id.isEmpty }
            next = try c.decodeIfPresent(String.self, forKey: .next)
        }

        private enum CodingKeys: String, CodingKey {
            case items, next
        }
    }

    let tracks: TracksPaging?
    let artists: ArtistsPaging?
    let albums: AlbumsPaging?
    let playlists: PlaylistsPaging?
}

/// Normalized first-page catalog search for the UI.
struct SpotifyCatalogSearchSnapshot: Sendable {
    var tracks: [SpotifyTrack]
    var artists: [SpotifySearchArtistItem]
    var albums: [SpotifySearchAlbumItem]
    var playlists: [SpotifyPlaylistItem]

    var isEmpty: Bool {
        tracks.isEmpty && artists.isEmpty && albums.isEmpty && playlists.isEmpty
    }

    /// Best-effort highlight: prefer a track match, then artist, album, playlist.
    var topResult: SpotifySearchTopResult? {
        if let t = tracks.first { return .track(t) }
        if let a = artists.first { return .artist(a) }
        if let al = albums.first { return .album(al) }
        if let p = playlists.first { return .playlist(p) }
        return nil
    }
}

enum SpotifySearchTopResult: Sendable {
    case track(SpotifyTrack)
    case artist(SpotifySearchArtistItem)
    case album(SpotifySearchAlbumItem)
    case playlist(SpotifyPlaylistItem)
}

struct SpotifyRecommendationsResponse: Decodable, Sendable {
    let tracks: [SpotifyTrack]
}

struct SpotifyPlaylistItem: Decodable, Sendable, Identifiable {
    struct PlaylistTracksRef: Decodable, Sendable {
        let total: Int?
    }

    struct SpotifyUserRef: Decodable, Sendable {
        let id: String?
    }

    let id: String
    let name: String
    let description: String?
    let images: [SpotifyImage]?
    let tracks: PlaylistTracksRef?
    /// Present on `GET /me/playlists` — used to explain Spotify’s access rules for playlist items.
    let collaborative: Bool?
    let owner: SpotifyUserRef?

    init(
        id: String,
        name: String,
        description: String?,
        images: [SpotifyImage]?,
        tracks: PlaylistTracksRef?,
        collaborative: Bool?,
        owner: SpotifyUserRef?
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.images = images
        self.tracks = tracks
        self.collaborative = collaborative
        self.owner = owner
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: PlaylistCodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description)
        images = try c.decodeIfPresent([SpotifyImage].self, forKey: .images)

        var tracksRef = try c.decodeIfPresent(PlaylistTracksRef.self, forKey: .tracks)
        if tracksRef == nil {
            /// Search responses may expose the track-count ref under `items` instead of `tracks` (same shape as `PlaylistTracksRef`).
            tracksRef = try? c.decode(PlaylistTracksRef.self, forKey: .items)
        }
        tracks = tracksRef

        collaborative = try c.decodeIfPresent(Bool.self, forKey: .collaborative)
        owner = try c.decodeIfPresent(SpotifyUserRef.self, forKey: .owner)
    }

    private enum PlaylistCodingKeys: String, CodingKey {
        case id, name, description, images, tracks, collaborative, owner, items
    }

    /// Best-resolution cover for display (Spotify returns several sizes; largest width is usually best).
    var coverURL: URL? {
        images?
            .compactMap { img -> (SpotifyImage, URL)? in
                guard let u = img.url else { return nil }
                return (img, u)
            }
            .max(by: { ($0.0.width ?? 0) < ($1.0.width ?? 0) })?
            .1
    }

    func replacingImages(_ newImages: [SpotifyImage]) -> SpotifyPlaylistItem {
        SpotifyPlaylistItem(
            id: id,
            name: name,
            description: description,
            images: newImages,
            tracks: tracks,
            collaborative: collaborative,
            owner: owner
        )
    }

    func replacingMetadata(name newName: String? = nil, description newDescription: String? = nil) -> SpotifyPlaylistItem {
        SpotifyPlaylistItem(
            id: id,
            name: newName ?? name,
            description: newDescription ?? description,
            images: images,
            tracks: tracks,
            collaborative: collaborative,
            owner: owner
        )
    }

    func isOwnedByCurrentUser(_ currentUserId: String?) -> Bool {
        guard let currentUserId, let ownerId = owner?.id else { return false }
        return ownerId == currentUserId
    }

    /// Spotify often surfaces the user's Liked Songs as a playlist; we show a dedicated sidebar row instead.
    var isLikelyLikedSongsMirror: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare("Liked Songs") == .orderedSame
    }

    /// Whether the current user can likely **change** this playlist via the Web API (add tracks, rename, …). Owners always; collaborative playlists may allow other editors.
    /// - Note: [Get Playlist Items](https://developer.spotify.com/documentation/web-api/reference/get-playlists-items) returns **403** for users who only *follow* a playlist (neither owner nor collaborator), even though `/v1/me/playlists` lists followed playlists.
    func isLikelyEditableByCurrentUser(currentUserId: String?) -> Bool {
        guard let currentUserId, let owner, let ownerId = owner.id else { return false }
        if ownerId == currentUserId { return true }
        return collaborative ?? false
    }
}

/// `GET /v1/me` — [Get Current User's Profile](https://developer.spotify.com/documentation/web-api/reference/get-current-users-profile).
struct SpotifyCurrentUser: Codable, Sendable {
    struct ExplicitContent: Codable, Sendable {
        let filter_enabled: Bool?
        let filter_locked: Bool?
    }

    struct ExternalURLs: Codable, Sendable {
        let spotify: URL?
    }

    struct Followers: Codable, Sendable {
        let href: String?
        let total: Int?
    }

    let country: String?
    let id: String
    let display_name: String?
    let email: String?
    let explicit_content: ExplicitContent?
    let external_urls: ExternalURLs?
    let followers: Followers?
    let href: String?
    let images: [SpotifyImage]?
    let product: String?
    let type: String?
    let uri: String?

    /// Shown name, or Spotify id if the user has no display name.
    var resolvedDisplayName: String {
        let trimmed = display_name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? id : trimmed
    }

    /// Images are widest-first; use a smaller asset for sidebar avatars.
    var profileImageURL: URL? {
        guard let images, !images.isEmpty else { return nil }
        return images.last?.url ?? images.first?.url
    }

    var spotifyProfileURL: URL? {
        external_urls?.spotify
    }
}

struct SpotifyPlaylistsPage: Decodable, Sendable {
    let items: [SpotifyPlaylistItem]
    let next: String?
}

/// `POST /v1/playlists/{playlist_id}/items` — [Add Items to Playlist](https://developer.spotify.com/documentation/web-api/reference/add-items-to-playlist).
struct SpotifyAddPlaylistItemsResponse: Decodable, Sendable {
    let snapshot_id: String
}

/// `GET /v1/me/tracks` — one page; `items[].track` may be `null` for unavailable items.
struct SpotifySavedTracksPage: Decodable, Sendable {
    struct Item: Decodable, Sendable {
        let track: SpotifyTrack?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            track = try? container.decodeIfPresent(SpotifyTrack.self, forKey: .track)
        }

        private enum CodingKeys: String, CodingKey {
            case track
        }
    }

    let items: [Item]
    let limit: Int?
    let offset: Int?
    let next: String?
    let total: Int?
}

/// `GET /v1/playlists/{id}/items` — [Get Playlist Items](https://developer.spotify.com/documentation/web-api/reference/get-playlists-items).
/// Spotify returns playlist rows under `items[].item`.
/// `GET /v1/me/player/recently-played` — [Get Recently Played Tracks](https://developer.spotify.com/documentation/web-api/reference/get-recently-played). Requires `user-read-recently-played`.
struct SpotifyRecentlyPlayedPage: Decodable, Sendable {
    struct Item: Decodable, Sendable {
        let track: SpotifyTrack?
        let played_at: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            track = try? container.decodeIfPresent(SpotifyTrack.self, forKey: .track)
            played_at = try? container.decodeIfPresent(String.self, forKey: .played_at)
        }

        private enum CodingKeys: String, CodingKey {
            case track
            case played_at
        }
    }

    let items: [Item]
    let next: String?
}

/// Normalized rows for UI lists (stable `id` per history event).
struct SpotifyRecentPlayRow: Identifiable, Sendable {
    let id: String
    let track: SpotifyTrack

    static func rows(from items: [SpotifyRecentlyPlayedPage.Item]) -> [SpotifyRecentPlayRow] {
        var rows: [SpotifyRecentPlayRow] = []
        rows.reserveCapacity(items.count)
        var displayIndex = 0
        for item in items {
            guard let track = item.track else { continue }
            if rows.last?.track.id == track.id { continue }
            let stamp = item.played_at ?? ""
            rows.append(SpotifyRecentPlayRow(id: "\(displayIndex)-\(stamp)-\(track.id)", track: track))
            displayIndex += 1
        }
        return rows
    }
}

struct SpotifyPlaylistTracksPage: Decodable, Sendable {
    struct Item: Decodable, Sendable {
        let item: SpotifyTrack?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            item = try? container.decodeIfPresent(SpotifyTrack.self, forKey: .item)
        }

        private enum CodingKeys: String, CodingKey {
            case item
        }
    }

    let items: [Item]
    let next: String?
}

/// `GET /v1/albums/{id}/tracks` — [Get an Album's Tracks](https://developer.spotify.com/documentation/web-api/reference/get-an-albums-tracks).
struct SpotifyAlbumTracksPage: Decodable, Sendable {
    let items: [SpotifyTrack]
    let next: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decodeIfPresent([SpotifyTrack?].self, forKey: .items) ?? []
        items = raw.compactMap { $0 }.filter { !$0.id.isEmpty }
        next = try c.decodeIfPresent(String.self, forKey: .next)
    }

    private enum CodingKeys: String, CodingKey {
        case items, next
    }
}

struct SpotifyAPIErrorBody: Codable, Sendable {
    let error: Detail?

    struct Detail: Codable, Sendable {
        let status: Int?
        let message: String?
    }
}

enum SpotifyAPIError: LocalizedError {
    case http(Int, String?)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case let .http(code, body):
            return "Spotify API error (\(code)): \(body ?? "")"
        case let .decoding(err):
            return "Failed to decode response: \(err.localizedDescription)"
        }
    }
}
