//
//  SpotifyPlayerAPI.swift
//  Lightify
//

import Foundation

/// Spotify Web API — Player endpoints (transfer, start, pause). Network work is off the main actor.
struct SpotifyPlayerAPI: Sendable {
    private let baseURL = SpotifyConfig.apiBaseURL

    /// `PUT /v1/me/player` — transfer playback to a device.
    func transferPlayback(accessToken: String, deviceId: String, play: Bool) async throws {
        let url = endpointURL("me/player")
        let body: [String: Any] = [
            "device_ids": [deviceId],
            "play": play,
        ]
        try await putJSON(url, accessToken: accessToken, body: body)
    }

    /// `PUT /v1/me/player/play` — start/resume playback (optionally on a specific device).
    func startPlayback(
        accessToken: String,
        deviceId: String?,
        uris: [String]?,
        contextURI: String?,
        positionMs: Int? = nil
    ) async throws {
        var components = URLComponents(url: endpointURL("me/player/play"), resolvingAgainstBaseURL: false)!
        if let deviceId {
            components.queryItems = [URLQueryItem(name: "device_id", value: deviceId)]
        }
        guard let url = components.url else {
            throw SpotifyAPIError.http(-1, nil)
        }
        var body: [String: Any] = [:]
        if let uris {
            body["uris"] = uris
        }
        if let contextURI {
            body["context_uri"] = contextURI
        }
        if let positionMs {
            body["position_ms"] = positionMs
        }
        try await putJSON(url, accessToken: accessToken, body: body.isEmpty ? nil : body)
    }

    /// `PUT /v1/me/player/pause`
    func pausePlayback(accessToken: String, deviceId: String?) async throws {
        var components = URLComponents(url: endpointURL("me/player/pause"), resolvingAgainstBaseURL: false)!
        if let deviceId {
            components.queryItems = [URLQueryItem(name: "device_id", value: deviceId)]
        }
        guard let url = components.url else {
            throw SpotifyAPIError.http(-1, nil)
        }
        try await putJSON(url, accessToken: accessToken, body: nil)
    }

    /// `PUT /v1/me/player/shuffle` — [Set shuffle mode](https://developer.spotify.com/documentation/web-api/reference/toggle-shuffle-for-users-playback). `state` is required.
    func setShuffleState(accessToken: String, enabled: Bool, deviceId: String?) async throws {
        var components = URLComponents(url: endpointURL("me/player/shuffle"), resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "state", value: enabled ? "true" : "false"),
        ]
        if let deviceId {
            items.append(URLQueryItem(name: "device_id", value: deviceId))
        }
        components.queryItems = items
        guard let url = components.url else {
            throw SpotifyAPIError.http(-1, nil)
        }
        try await putJSON(url, accessToken: accessToken, body: nil)
    }

    /// `PUT /v1/me/player/repeat` — [Set repeat mode](https://developer.spotify.com/documentation/web-api/reference/set-repeat-mode-on-users-playback). `state` is `track`, `context`, or `off`.
    func setRepeatMode(accessToken: String, state: String, deviceId: String?) async throws {
        var components = URLComponents(url: endpointURL("me/player/repeat"), resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "state", value: state),
        ]
        if let deviceId {
            items.append(URLQueryItem(name: "device_id", value: deviceId))
        }
        components.queryItems = items
        guard let url = components.url else {
            throw SpotifyAPIError.http(-1, nil)
        }
        try await putJSON(url, accessToken: accessToken, body: nil)
    }

    private func putJSON(_ url: URL, accessToken: String, body: [String: Any]?) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        }

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SpotifyAPIError.http(-1, nil)
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw SpotifyAPIError.http(http.statusCode, nil)
        }
    }

    private func endpointURL(_ path: String) -> URL {
        baseURL.appending(path: path)
    }
}
