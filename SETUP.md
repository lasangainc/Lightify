# Lightify — Spotify setup

## 1. Spotify Developer Dashboard

1. Create an app at [Spotify Developer Dashboard](https://developer.spotify.com/dashboard).
2. When creating the app, you can indicate use of **Web Playback SDK** (recommended for this project).
3. Open the app → **Settings** → **Redirect URIs** → add exactly:
   - `lightify://oauth-callback`
4. Copy the **Client ID** into `Lightify/Spotify/SpotifyConfig.swift` (`SpotifyConfig.clientID`).

## 2. Run the app

- Build and run the **Lightify** macOS target.
- First launch: tap **Log in with Spotify** and complete the browser flow (scopes include playback + library).
- **Playback** uses the [Spotify Web Playback SDK](https://developer.spotify.com/documentation/web-playback-sdk) inside a hidden `WKWebView`. A **Spotify Premium** account is required for Web Playback.

## 3. Re-authorization after scope changes

If you previously signed in with older scopes, the app will ask you to **sign in again** so Spotify can grant the playback-related permissions (including **library read/modify** if you use Liked Songs or the heart control to save tracks).

Saving tracks uses Spotify’s current **[Save Items to Library](https://developer.spotify.com/documentation/web-api/reference/save-library-items)** endpoint (`PUT /v1/me/library` with `uris=spotify:track:…`), not the deprecated `PUT /v1/me/tracks`. If you still see **403 Forbidden** after a fresh sign-in, confirm the app’s scopes in the dashboard include `user-library-modify` and that you completed the consent screen for this app.
