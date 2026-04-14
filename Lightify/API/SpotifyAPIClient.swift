//
//  SpotifyAPIClient.swift
//  Lightify
//

import Foundation

/// Thin Spotify Web API wrapper (network work runs off the main actor).
struct SpotifyAPIClient: Sendable {
    private let baseURL = SpotifyConfig.apiBaseURL

    /// `GET /v1/search` — catalog search for tracks, artists, albums, and playlists. Requires a valid user access token.
    /// - Note: Search accepts `limit` **0…10** per item type (unlike many other endpoints that allow up to 50).
    func searchCatalog(
        accessToken: String,
        query: String,
        limit: Int = 10,
        offset: Int = 0
    ) async throws -> SpotifyCatalogSearchSnapshot {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return SpotifyCatalogSearchSnapshot(tracks: [], artists: [], albums: [], playlists: [])
        }
        precondition((0 ... 1000).contains(offset), "Spotify docs: offset must be 0...1000")
        let clampedLimit = min(max(limit, 1), 10)
        var components = URLComponents(url: endpointURL("search"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "type", value: "track,artist,album,playlist"),
            URLQueryItem(name: "limit", value: String(clampedLimit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        let response: SpotifySearchCatalogResponse = try await get(components.url!, accessToken: accessToken)
        return SpotifyCatalogSearchSnapshot(
            tracks: response.tracks?.items ?? [],
            artists: response.artists?.items ?? [],
            albums: response.albums?.items ?? [],
            playlists: response.playlists?.items ?? []
        )
    }

    func fetchTopTracks(accessToken: String, limit: Int = 5, timeRange: String = "medium_term") async throws -> [SpotifyTrack] {
        var components = URLComponents(url: endpointURL("me/top/tracks"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "time_range", value: timeRange),
        ]
        let page: SpotifyTracksPage = try await get(components.url!, accessToken: accessToken)
        return page.items
    }

    /// `GET /v1/me/player/queue` — upcoming tracks for the active playback session.
    func fetchPlaybackQueue(accessToken: String) async throws -> SpotifyPlayerQueueResponse {
        try await get(endpointURL("me/player/queue"), accessToken: accessToken)
    }

    /// `GET /v1/recommendations`
    /// - Note: As of Spotify’s [Nov 2024 Web API changes](https://developer.spotify.com/blog/2024-11-27-changes-to-the-web-api), **new apps** and apps still in **development mode** (without extended access) receive **404** for this endpoint. Callers should fall back (e.g. show the user’s top tracks).
    func fetchRecommendations(accessToken: String, seedTrackIDs: [String], limit: Int = 20) async throws -> [SpotifyTrack] {
        guard !seedTrackIDs.isEmpty else { return [] }
        var components = URLComponents(url: endpointURL("recommendations"), resolvingAgainstBaseURL: false)!
        let seeds = seedTrackIDs.prefix(5).joined(separator: ",")
        components.queryItems = [
            URLQueryItem(name: "seed_tracks", value: seeds),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        let response: SpotifyRecommendationsResponse = try await get(components.url!, accessToken: accessToken)
        return response.tracks
    }

    func fetchUserPlaylists(accessToken: String, limit: Int = 30) async throws -> [SpotifyPlaylistItem] {
        var components = URLComponents(url: endpointURL("me/playlists"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        let page: SpotifyPlaylistsPage = try await get(components.url!, accessToken: accessToken)
        return page.items
    }

    /// `GET /v1/playlists/{playlist_id}/images` — [Get Playlist Cover Image](https://developer.spotify.com/documentation/web-api/reference/get-playlist-cover).
    func fetchPlaylistCoverImages(accessToken: String, playlistID: String) async throws -> [SpotifyImage] {
        try await get(endpointURL("playlists/\(playlistID)/images"), accessToken: accessToken)
    }

    /// `GET /v1/me` — [Get Current User's Profile](https://developer.spotify.com/documentation/web-api/reference/get-current-users-profile). Used to interpret playlist ownership vs followed-only playlists.
    func fetchCurrentUser(accessToken: String) async throws -> SpotifyCurrentUser {
        try await get(endpointURL("me"), accessToken: accessToken)
    }

    /// `GET /v1/artists/{id}` — [Get Artist](https://developer.spotify.com/documentation/web-api/reference/get-an-artist).
    func fetchArtist(accessToken: String, id: String) async throws -> SpotifyArtistProfile {
        try await get(endpointURL("artists/\(id)"), accessToken: accessToken)
    }

    /// `GET /v1/artists/{id}/top-tracks` — [Get Artist's Top Tracks](https://developer.spotify.com/documentation/web-api/reference/get-an-artists-top-tracks). `market` is required.
    func fetchArtistTopTracks(accessToken: String, artistID: String, market: String) async throws -> [SpotifyTrack] {
        var components = URLComponents(url: endpointURL("artists/\(artistID)/top-tracks"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "market", value: market),
        ]
        let response: SpotifyArtistTopTracksResponse = try await get(components.url!, accessToken: accessToken)
        return response.tracks
    }

    /// `GET /v1/tracks/{id}` — metadata including album images (for Now Playing artwork fallback).
    func fetchTrack(accessToken: String, id: String) async throws -> SpotifyTrack {
        try await get(endpointURL("tracks/\(id)"), accessToken: accessToken)
    }

    /// `GET /v1/albums/{id}` — [Get Album](https://developer.spotify.com/documentation/web-api/reference/get-an-album).
    func fetchAlbum(accessToken: String, albumID: String, market: String? = nil) async throws -> SpotifyAlbum {
        var components = URLComponents(url: endpointURL("albums/\(albumID)"), resolvingAgainstBaseURL: false)!
        var query: [URLQueryItem] = []
        if let market, !market.isEmpty {
            query.append(URLQueryItem(name: "market", value: market))
        }
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else {
            throw SpotifyAPIError.http(-1, "Invalid album URL")
        }
        return try await get(url, accessToken: accessToken)
    }

    /// `GET /v1/albums/{id}/tracks` — one page; follows `next` in `fetchAllAlbumTracks`.
    func fetchAlbumTracksPage(
        accessToken: String,
        albumID: String,
        limit: Int = 50,
        offset: Int = 0,
        market: String? = nil
    ) async throws -> SpotifyAlbumTracksPage {
        precondition((1 ... 50).contains(limit), "Spotify docs: limit must be 1...50")
        var components = URLComponents(url: endpointURL("albums/\(albumID)/tracks"), resolvingAgainstBaseURL: false)!
        var query: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        if let market, !market.isEmpty {
            query.append(URLQueryItem(name: "market", value: market))
        }
        components.queryItems = query
        return try await get(components.url!, accessToken: accessToken)
    }

    /// Fetches all tracks on an album by following each page’s `next` URL.
    func fetchAllAlbumTracks(accessToken: String, albumID: String, market: String? = nil) async throws -> [SpotifyTrack] {
        var all: [SpotifyTrack] = []
        var url: URL? = {
            var c = URLComponents(url: endpointURL("albums/\(albumID)/tracks"), resolvingAgainstBaseURL: false)!
            var query: [URLQueryItem] = [
                URLQueryItem(name: "limit", value: "50"),
                URLQueryItem(name: "offset", value: "0"),
            ]
            if let market, !market.isEmpty {
                query.append(URLQueryItem(name: "market", value: market))
            }
            c.queryItems = query
            return c.url
        }()
        while let current = url {
            let page: SpotifyAlbumTracksPage = try await get(current, accessToken: accessToken)
            all.append(contentsOf: page.items)
            if let next = page.next, let nextURL = URL(string: next) {
                url = nextURL
            } else {
                url = nil
            }
        }
        return all
    }

    /// `GET /v1/me/tracks` — [Get User's Saved Tracks](https://developer.spotify.com/documentation/web-api/reference/get-users-saved-tracks). Requires `user-library-read`.
    func fetchSavedTracksPage(accessToken: String, limit: Int = 50, offset: Int = 0) async throws -> SpotifySavedTracksPage {
        precondition((1 ... 50).contains(limit), "Spotify docs: limit must be 1...50")
        var components = URLComponents(url: endpointURL("me/tracks"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        return try await get(components.url!, accessToken: accessToken)
    }

    /// Fetches the full saved-track id set using a trimmed response shape so heart state stays accurate without holding every full track payload in memory.
    func fetchAllSavedTrackIDs(accessToken: String) async throws -> [String] {
        struct SavedTrackIDsPage: Decodable {
            struct Item: Decodable {
                struct TrackRef: Decodable {
                    let id: String?
                }

                let track: TrackRef?
            }

            let items: [Item]
            let next: String?
        }

        var ids: [String] = []
        var url: URL? = {
            var c = URLComponents(url: endpointURL("me/tracks"), resolvingAgainstBaseURL: false)!
            c.queryItems = [
                URLQueryItem(name: "limit", value: "50"),
                URLQueryItem(name: "offset", value: "0"),
                URLQueryItem(name: "fields", value: "items(track(id)),next"),
            ]
            return c.url
        }()

        while let current = url {
            let page: SavedTrackIDsPage = try await get(current, accessToken: accessToken)
            for item in page.items {
                if let id = item.track?.id, !id.isEmpty {
                    ids.append(id)
                }
            }
            if let next = page.next, let nextURL = URL(string: next) {
                url = nextURL
            } else {
                url = nil
            }
        }
        return ids
    }

    /// `GET /v1/me/player/recently-played` — requires `user-read-recently-played`.
    func fetchRecentlyPlayed(accessToken: String, limit: Int = 50) async throws -> [SpotifyRecentlyPlayedPage.Item] {
        precondition((1 ... 50).contains(limit), "Spotify docs: limit must be 1...50")
        var components = URLComponents(url: endpointURL("me/player/recently-played"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        let page: SpotifyRecentlyPlayedPage = try await get(components.url!, accessToken: accessToken)
        return page.items
    }

    /// Fetches all saved tracks by following each page’s `next` URL (Spotify’s paging contract).
    func fetchAllSavedTracks(accessToken: String) async throws -> [SpotifyTrack] {
        var all: [SpotifyTrack] = []
        var url: URL? = {
            var c = URLComponents(url: endpointURL("me/tracks"), resolvingAgainstBaseURL: false)!
            c.queryItems = [
                URLQueryItem(name: "limit", value: "50"),
                URLQueryItem(name: "offset", value: "0"),
            ]
            return c.url
        }()
        while let current = url {
            let page: SpotifySavedTracksPage = try await get(current, accessToken: accessToken)
            for item in page.items {
                if let t = item.track {
                    all.append(t)
                }
            }
            if let next = page.next, let nextURL = URL(string: next) {
                url = nextURL
            } else {
                url = nil
            }
        }
        return all
    }

    /// `GET /v1/me/tracks/contains` — [Check User's Saved Tracks](https://developer.spotify.com/documentation/web-api/reference/check-users-saved-tracks). Up to 50 IDs per request. Requires `user-library-read`.
    func checkSavedTracks(accessToken: String, trackIDs: [String]) async throws -> [Bool] {
        guard !trackIDs.isEmpty else { return [] }
        precondition(trackIDs.count <= 50, "Spotify docs: max 50 ids per request")
        var components = URLComponents(url: endpointURL("me/tracks/contains"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "ids", value: trackIDs.joined(separator: ",")),
        ]
        return try await get(components.url!, accessToken: accessToken)
    }

    /// `PUT /v1/me/library` — [Save Items to Library](https://developer.spotify.com/documentation/web-api/reference/save-library-items).
    /// Passes track IDs as `spotify:track:{id}` URIs in the `uris` query parameter (max 40 per request). Requires `user-library-modify`.
    /// - Note: `PUT /v1/me/tracks` is deprecated; Spotify recommends this endpoint.
    func saveTracks(accessToken: String, trackIDs: [String]) async throws {
        guard !trackIDs.isEmpty else { return }
        precondition(trackIDs.count <= 40, "Spotify docs: max 40 URIs per request for /me/library")
        let url = try libraryMutationURL(trackIDs: trackIDs)
        try await mutate(url: url, accessToken: accessToken, method: "PUT", jsonBody: nil)
    }

    /// `DELETE /v1/me/library` — [Remove Items from Library](https://developer.spotify.com/documentation/web-api/reference/remove-library-items).
    /// Same URI format as `saveTracks`. Requires `user-library-modify`.
    func removeSavedTracks(accessToken: String, trackIDs: [String]) async throws {
        guard !trackIDs.isEmpty else { return }
        precondition(trackIDs.count <= 40, "Spotify docs: max 40 URIs per request for /me/library")
        let url = try libraryMutationURL(trackIDs: trackIDs)
        try await mutate(url: url, accessToken: accessToken, method: "DELETE", jsonBody: nil)
    }

    private func libraryMutationURL(trackIDs: [String]) throws -> URL {
        let uris = trackIDs.map { "spotify:track:\($0)" }.joined(separator: ",")
        var components = URLComponents(url: endpointURL("me/library"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "uris", value: uris)]
        guard let url = components.url else {
            throw SpotifyAPIError.http(-1, "Invalid library URL")
        }
        return url
    }

    /// `GET /v1/playlists/{playlist_id}/items` — [Get Playlist Items](https://developer.spotify.com/documentation/web-api/reference/get-playlists-items).
    /// OpenAPI: optional query params `market`, `fields`, `limit`, `offset`, `additional_types` (omit `additional_types` unless you also need `episode` items—default is tracks).
    /// Security scope: `playlist-read-private`. Reference: **403** if the user is neither the playlist owner nor a collaborator.
    func fetchPlaylistTracksPage(
        accessToken: String,
        playlistID: String,
        limit: Int = 50,
        offset: Int = 0,
        market: String? = nil
    ) async throws -> SpotifyPlaylistTracksPage {
        precondition((1 ... 50).contains(limit), "Spotify docs: limit must be 1...50")
        var components = URLComponents(
            url: endpointURL("playlists/\(playlistID)/items"),
            resolvingAgainstBaseURL: false
        )!
        var query: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        if let market, !market.isEmpty {
            query.append(URLQueryItem(name: "market", value: market))
        }
        components.queryItems = query
        return try await get(components.url!, accessToken: accessToken)
    }

    /// `POST /v1/me/playlists` — [Create Playlist](https://developer.spotify.com/documentation/web-api/reference/create-playlist).
    func createPlaylist(
        accessToken: String,
        name: String,
        isPublic: Bool,
        description: String? = nil
    ) async throws -> SpotifyPlaylistItem {
        struct Body: Encodable {
            let name: String
            let isPublic: Bool
            let description: String?

            enum CodingKeys: String, CodingKey {
                case name
                case isPublic = "public"
                case description
            }
        }
        let body = Body(name: name, isPublic: isPublic, description: description)
        let data = try JSONEncoder().encode(body)
        return try await postJSON(
            url: endpointURL("me/playlists"),
            accessToken: accessToken,
            jsonBody: data,
            responseType: SpotifyPlaylistItem.self
        )
    }

    /// `PUT /v1/playlists/{playlist_id}` — [Change Playlist Details](https://developer.spotify.com/documentation/web-api/reference/change-playlist-details).
    func renamePlaylist(accessToken: String, playlistID: String, name: String) async throws {
        struct Body: Encodable {
            let name: String
        }

        let data = try JSONEncoder().encode(Body(name: name))
        try await mutate(
            url: endpointURL("playlists/\(playlistID)"),
            accessToken: accessToken,
            method: "PUT",
            jsonBody: data
        )
    }

    /// `DELETE /v1/playlists/{playlist_id}/followers` — Spotify "deletes" a playlist by unfollowing it.
    func deletePlaylist(accessToken: String, playlistID: String) async throws {
        try await mutate(
            url: endpointURL("playlists/\(playlistID)/followers"),
            accessToken: accessToken,
            method: "DELETE",
            jsonBody: nil
        )
    }

    /// `POST /v1/playlists/{playlist_id}/items` — [Add Items to Playlist](https://developer.spotify.com/documentation/web-api/reference/add-items-to-playlist).
    func addItemsToPlaylist(accessToken: String, playlistID: String, trackURIs: [String]) async throws -> String {
        guard !trackURIs.isEmpty else { return "" }
        precondition(trackURIs.count <= 100, "Spotify docs: max 100 items per request")
        struct Body: Encodable {
            let uris: [String]
        }
        let data = try JSONEncoder().encode(Body(uris: trackURIs))
        let response: SpotifyAddPlaylistItemsResponse = try await postJSON(
            url: endpointURL("playlists/\(playlistID)/items"),
            accessToken: accessToken,
            jsonBody: data,
            responseType: SpotifyAddPlaylistItemsResponse.self
        )
        return response.snapshot_id
    }

    /// `PUT /v1/playlists/{playlist_id}/images` — [Add Custom Playlist Cover Image](https://developer.spotify.com/documentation/web-api/reference/upload-custom-playlist-cover).
    /// - Note: Request body is **base64-encoded JPEG** bytes as UTF-8; Spotify documents a **256 KB** maximum payload size.
    func uploadPlaylistCoverImage(accessToken: String, playlistID: String, jpegData: Data) async throws {
        let base64 = jpegData.base64EncodedString()
        guard let body = base64.data(using: .utf8) else {
            throw SpotifyAPIError.http(-1, "Could not encode cover payload")
        }
        guard body.count <= 256 * 1024 else {
            throw SpotifyAPIError.http(-1, "Cover image is too large for Spotify (max 256 KB after base64).")
        }
        try await putRaw(
            url: endpointURL("playlists/\(playlistID)/images"),
            accessToken: accessToken,
            contentType: "image/jpeg",
            body: body
        )
    }

    /// Fetches all tracks in a playlist (skips non-track rows and null tracks). Follows each page’s `next` URL as returned by Spotify.
    func fetchAllPlaylistTracks(accessToken: String, playlistID: String, market: String? = nil) async throws -> [SpotifyTrack] {
        var all: [SpotifyTrack] = []
        var url: URL? = {
            var c = URLComponents(
                url: endpointURL("playlists/\(playlistID)/items"),
                resolvingAgainstBaseURL: false
            )!
            var query: [URLQueryItem] = [
                URLQueryItem(name: "limit", value: "50"),
                URLQueryItem(name: "offset", value: "0"),
            ]
            if let market, !market.isEmpty {
                query.append(URLQueryItem(name: "market", value: market))
            }
            c.queryItems = query
            return c.url
        }()
        while let current = url {
            let page: SpotifyPlaylistTracksPage = try await get(current, accessToken: accessToken)
            for item in page.items {
                if let t = item.item {
                    all.append(t)
                }
            }
            if let next = page.next, let nextURL = URL(string: next) {
                url = nextURL
            } else {
                url = nil
            }
        }
        return all
    }

    private func postJSON<T: Decodable>(
        url: URL,
        accessToken: String,
        jsonBody: Data,
        responseType: T.Type
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonBody

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SpotifyAPIError.http(-1, nil)
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8)
            throw SpotifyAPIError.http(http.statusCode, text)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw SpotifyAPIError.decoding(error)
        }
    }

    private func putRaw(url: URL, accessToken: String, contentType: String, body: Data) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SpotifyAPIError.http(-1, nil)
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8)
            throw SpotifyAPIError.http(http.statusCode, text)
        }
    }

    private func mutate(url: URL, accessToken: String, method: String, jsonBody: Data?) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let jsonBody {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = jsonBody
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SpotifyAPIError.http(-1, nil)
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8)
            throw SpotifyAPIError.http(http.statusCode, text)
        }
    }

    private func get<T: Decodable>(_ url: URL, accessToken: String) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SpotifyAPIError.http(-1, nil)
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8)
            throw SpotifyAPIError.http(http.statusCode, text)
        }
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            throw SpotifyAPIError.decoding(error)
        }
    }

    private func endpointURL(_ path: String) -> URL {
        baseURL.appending(path: path)
    }
}
