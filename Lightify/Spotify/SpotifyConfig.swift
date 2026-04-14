//
//  SpotifyConfig.swift
//  Lightify
//

import Foundation

/// Client ID from the [Spotify Developer Dashboard](https://developer.spotify.com/dashboard).
/// Register redirect URI: `lightify://oauth-callback` (must match exactly).
/// Token exchange uses PKCE only; do not embed a client secret in the app.
enum SpotifyConfig {
    static let clientID = "a418bc5b662043eb81874a53bd2a5382"
    /// Must match `CFBundleURLSchemes` in Info.plist (`lightify`) and the redirect URI in the Spotify app settings.
    static let redirectURI = "lightify://oauth-callback"

    static let authorizeURL = URL(string: "https://accounts.spotify.com/authorize")!
    static let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!
    static let apiBaseURL = URL(string: "https://api.spotify.com/v1")!

    /// Library + Web Playback SDK + player control (transfer/start playback).
    static let scopes = [
        "user-top-read",
        "user-library-read",
        "user-library-modify",
        "user-read-private",
        "user-read-email",
        "user-read-recently-played",
        "playlist-read-private",
        "playlist-read-collaborative",
        "playlist-modify-private",
        "playlist-modify-public",
        "ugc-image-upload",
        "streaming",
        "user-modify-playback-state",
        "user-read-playback-state",
    ]

    static var redirectURIComponents: URLComponents {
        var c = URLComponents()
        c.scheme = "lightify"
        c.host = "oauth-callback"
        return c
    }
}
