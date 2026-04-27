# Lightify: APIs, features, and Electron translation notes

This document inventories **network endpoints**, **in-app features**, and **presentation patterns** used by Lightify (macOS SwiftUI). It is written so an Electron (or other web-desktop) port can mirror behavior without re-reading the whole codebase.

---

## 1. High-level architecture

| Concern | Current (Lightify) | Electron analogue |
|--------|---------------------|---------------------|
| UI | SwiftUI (`ContentView`, `DashboardView`, etc.) | HTML/CSS + React/Vue/Svelte, or a small web app in `BrowserWindow` |
| Spotify REST | `URLSession` in `SpotifyAPIClient`, `SpotifyPlayerAPI` | `fetch` in main or renderer; prefer **main process** + IPC for tokens |
| OAuth | `ASWebAuthenticationSession` + PKCE (`SpotifyAuthService`) | `BrowserWindow` OAuth or system browser + custom protocol / deep link (`app.setAsDefaultProtocolClient`) |
| Token storage | Keychain (`SpotifyTokenStore`) | `safeStorage` or OS keychain via a native module |
| Audio playback | **Spotify Web Playback SDK** inside `WKWebView` (`web_player.html` + `web_player.js`, `SpotifyWebPlaybackBridge`) | **Hidden `BrowserView` / off-screen window** loading the same SDK, or a dedicated player window; bridge with `contextBridge` / IPC |
| Now Playing / media keys | `SystemNowPlayingCoordinator` (AppKit) | `MediaSession` API + global shortcuts (`globalShortcut`) |
| Lyrics | `GeniusLyricsService` (HTTP + HTML parse) | Same HTTP logic in Node or renderer; respect Genius ToS and rate limits in production |

---

## 2. Authentication and token lifecycle

### 2.1 OAuth (Authorization Code + PKCE)

| Step | URL / action |
|------|----------------|
| Authorize | `GET https://accounts.spotify.com/authorize` — query: `client_id`, `response_type=code`, `redirect_uri`, `scope` (space-separated), `code_challenge_method=S256`, `code_challenge`, `state` |
| Token exchange | `POST https://accounts.spotify.com/api/token` — `Content-Type: application/x-www-form-urlencoded`; body includes `grant_type=authorization_code`, `code`, `redirect_uri`, `client_id`, `code_verifier` |
| Refresh | Same token URL with `grant_type=refresh_token`, `refresh_token`, `client_id` |

**Redirect URI** (must match Spotify Dashboard and app registration): `lightify://oauth-callback` (scheme `lightify`, host `oauth-callback`). For Electron, register a custom protocol (e.g. `lightify://` or `app://`) and parse `code` / `state` / `error` from the callback URL.

**Client credentials**: PKCE only; **no client secret** in the app (same for Electron).

### 2.2 Scopes (`SpotifyConfig.scopes`)

These drive which Web API calls succeed:

- `user-top-read`
- `user-library-read`, `user-library-modify`
- `user-read-private`, `user-read-email`
- `user-read-recently-played`
- `playlist-read-private`, `playlist-read-collaborative`
- `playlist-modify-private`, `playlist-modify-public`
- `ugc-image-upload` (custom playlist covers)
- `streaming`
- `user-modify-playback-state`, `user-read-playback-state`

### 2.3 Session rules (mirror in Electron)

- Refresh access token when near expiry (app uses ~30s skew before expiry).
- On `401` from Web API: refresh once, retry; if refresh fails → treat as session expired, sign out.
- Persisted session must satisfy **required scopes** subset check; otherwise force re-login.

---

## 3. Spotify Web API base

All REST paths are under:

**`https://api.spotify.com/v1`**

Default header for API calls:

```http
Authorization: Bearer <access_token>
```

JSON request bodies use `Content-Type: application/json` where applicable.

---

## 4. Spotify Web API endpoints (as used by Lightify)

### 4.1 Catalog and user profile

| Method | Path | Purpose in app |
|--------|------|----------------|
| `GET` | `/me` | Current user profile; `country` used as ISO market fallback for artist/album/playlist calls |
| `GET` | `/search` | Multi-type catalog search (`type=track,artist,album,playlist`; limit **1–10** per Search docs); also `type=track` only for artist fallback |
| `GET` | `/recommendations` | **Implemented** in `SpotifyAPIClient.fetchRecommendations` (`seed_tracks`, `limit`); may **404** for new/dev-mode Spotify apps (Nov 2024 policy) — not wired to primary UI in current tree |
| `GET` | `/me/top/tracks` | User’s top tracks (`limit`, `time_range`) |

### 4.2 Library (saved tracks)

| Method | Path | Purpose |
|--------|------|---------|
| `GET` | `/me/tracks` | Paginated liked songs; optional `fields` for lightweight ID-only paging |
| `PUT` | `/me/library` | Save tracks (`uris` query: `spotify:track:{id}`, max **40** per request) — preferred over deprecated `PUT /me/tracks` |
| `DELETE` | `/me/library` | Remove saved tracks (same URI format) |
| `GET` | `/me/tracks/contains` | Heart state for up to **50** track IDs (`ids` comma-separated) |

### 4.3 History and queue

| Method | Path | Purpose |
|--------|------|---------|
| `GET` | `/me/player/recently-played` | Home “Recently played” |
| `GET` | `/me/player/queue` | “Up next” UI (`SpotifyPlayerQueueResponse`) |

### 4.4 Playlists

| Method | Path | Purpose |
|--------|------|---------|
| `GET` | `/me/playlists` | Sidebar library playlists |
| `GET` | `/playlists/{id}/items` | Playlist track listing (paginated; `market` optional); **403** when user cannot read items (followed-only / permissions) |
| `GET` | `/playlists/{id}/images` | Cover art when `/me/playlists` omits images |
| `POST` | `/me/playlists` | Create playlist (JSON: `name`, `public`, `description`) |
| `PUT` | `/playlists/{id}` | Rename (`name` in JSON) |
| `DELETE` | `/playlists/{id}/followers` | “Delete” playlist (unfollow) |
| `POST` | `/playlists/{id}/items` | Add tracks (`uris` array, max **100**) |
| `DELETE` | `/playlists/{id}/items` | Remove tracks (JSON `items: [{ uri }]`, max **100**; removes **all** occurrences per Spotify) |
| `PUT` | `/playlists/{id}/images` | Custom cover: body is **base64(JPEG)** as UTF-8 bytes, `Content-Type: image/jpeg`, max **256 KB** payload |

### 4.5 Albums and tracks

| Method | Path | Purpose |
|--------|------|---------|
| `GET` | `/tracks/{id}` | Full track + album when opening album from partial payloads |
| `GET` | `/albums/{id}` | Album header metadata (`market` optional) |
| `GET` | `/albums/{id}/tracks` | Album track list (paginated; `market` optional) |

### 4.6 Artists

| Method | Path | Purpose |
|--------|------|---------|
| `GET` | `/artists/{id}` | Artist profile |
| `GET` | `/artists/{id}/top-tracks` | Top tracks (**`market` required**); app tries `market=from_token`, on **400** retries with user’s ISO country from `/me` |
| `GET` | `/artists/{id}/albums` | Discography slice (`include_groups`, `market`, paging); same `from_token` → ISO fallback pattern |

---

## 5. Spotify Web API — Player controls

Implemented in `SpotifyPlayerAPI`. Calls typically include `device_id` query when targeting the **Web Playback** device.

| Method | Path | Body / query |
|--------|------|--------------|
| `PUT` | `/me/player` | JSON: `device_ids: [id]`, `play: bool` — **implemented** (`transferPlayback`); verify if your port needs explicit transfer |
| `PUT` | `/me/player/play` | Query: `device_id` optional; JSON: `uris` and/or `context_uri`, optional `position_ms` |
| `PUT` | `/me/player/pause` | Query: `device_id` optional |
| `PUT` | `/me/player/shuffle` | Query: `state=true|false`, optional `device_id` |
| `PUT` | `/me/player/repeat` | Query: `state=track|context|off`, optional `device_id` |

**Playback orchestration in app:**

- **Start** track / context / URI list: `PUT /me/player/play` with Web Playback `device_id`.
- **Local transport**: play/pause/next/previous/seek/volume use **Web Playback SDK** JS (`web_player.js`) on the embedded player, not REST.
- **Shuffle / repeat**: Web API `shuffle` + `repeat` (state from SDK updates UI).

---

## 6. Web Playback SDK bridge (critical for Electron)

### 6.1 Loader

- HTML loads `https://sdk.scdn.co/spotify-player.js` then local `web_player.js`.
- Player name: **`Lightify`**.

### 6.2 Native ↔ JS contract

**Outbound (host → page):** evaluate JS calling globals:

- `lightifyStartPlayer()`, `lightifyDeliverToken(token)`, `lightifyActivateElement()`, `lightifyTogglePlay()`, `lightifyPlay()`, `lightifyPause()`, `lightifyNext()`, `lightifyPrevious()`, `lightifyDisconnect()`, `lightifySetVolume(0…1)`, `lightifySeek(ms)`

**Inbound (page → host):** JSON string posted to a named handler (WebKit: `webkit.messageHandlers.lightifySpotify`).

Message `type` values: `sdk_ready`, `connect_result`, `ready`, `not_ready`, `player_state_changed`, `autoplay_failed`, `initialization_error`, `authentication_error`, `account_error`, `playback_error`, `need_token`, `log`.

On `need_token`, host must async-fetch a fresh access token and call `lightifyDeliverToken`. Empty token signals failure.

### 6.3 Electron mapping

- Use a **hidden** `BrowserView` or `webview` with **nodeIntegration: false**, **contextIsolation: true**, preload exposing `ipcRenderer.invoke('spotify:get-token')`.
- Reuse `web_player.js` with a thin adapter: replace `post()` to use `window.electronAPI.postToHost(JSON.stringify(message))` instead of `webkit.messageHandlers`.
- Enable autoplay policies: Chromium flags or user gesture chaining similar to `mediaTypesRequiringUserActionForPlayback = []` on macOS WebKit.

---

## 7. Genius (lyrics) — unofficial HTTP usage

Not Spotify; no API key in repo.

| Step | URL | Notes |
|------|-----|--------|
| Direct page guess | `GET https://genius.com/{artist-slug}-{title-slug}-lyrics` | Browser-like `User-Agent` and `Accept: text/html` |
| Search fallback | `GET https://genius.com/api/search/multi?q=...` | JSON; score best `type=song` hit |
| Parse | N/A | Read `<main>`, find `data-lyrics-container="true"`, strip tags, decode entities, slice from first `[` for section markers |

**Electron:** run same logic in main process (cheerio/jsdom) or renderer; cache responses; handle CORS if calling from renderer (prefer main).

---

## 8. Product features (functional inventory)

### 8.1 App phases

1. **Bootstrapping** — load Keychain session, optional refresh, validate scopes.
2. **Needs login** — OAuth sheet over branded backdrop.
3. **Loading content** — fetch playlists, first liked page, all liked IDs, recently played, `/me`.
4. **Ready** — main dashboard + hidden web player host.

### 8.2 Navigation model

- **Sidebar** (`LibrarySelection`): Home, Profile, Liked Songs, Search, user playlists, album detail, artist detail.
- **Detail column**: track lists, search results, album/artist content; **bottom safe area**: now playing bar (`NowPlayingControls`).
- **Album detail**: optional back to previous selection; opens from track rows, search, playback context (`spotify:album:…` or resolved from track).

### 8.3 Home

- Horizontal **liked songs** carousel (play track; artwork tap → album).
- **Recently played** list (play; artist/album navigation).

### 8.4 Liked songs

- Windowed list with **infinite scroll** prefetch; total count from API.
- **Heart** toggle with optimistic UI (`PUT`/`DELETE` `/me/library`).

### 8.5 Search

- Tabs: All, Songs, Artists, Albums, Playlists.
- Single catalog search request; client-side tab filtering / layout.

### 8.6 Playlists

- List user playlists; open playlist loads **all** tracks (paged until end) unless **403** — then show message: playback context may still work via Web Playback even when track list is hidden.
- **Create** playlist (name, public/private, description, optional JPEG cover upload).
- **Add** track to playlist, **remove** track (with list animation).
- **Rename** / **unfollow (delete)** for editable playlists; heuristics exclude “Liked Songs mirror” and non-owned read-only lists.

### 8.7 Albums

- Fetch album metadata + all tracks; partial failure surfaces **warnings** without blocking the whole screen when possible.

### 8.8 Artists

- Profile + top tracks + albums; **market** fallback; if top tracks empty, **search** fallback filtered by artist ID.

### 8.9 Playback

- Play **single track**, **context** (`spotify:album:`, `spotify:playlist:`, `spotify:artist:`), or **bounded URI list** (e.g. liked songs, capped at 100 URIs per request).
- Mini player window (separate UI surface) with optional **lyrics panel** (`GeniusLyricsService`).
- Progress scrubber with **local extrapolation** between SDK ticks (~250 ms).
- **Queue** panel: refresh from `GET /me/player/queue`.
- Shuffle / repeat toggles via REST; state reflected from SDK `player_state_changed`.
- Error handling: autoplay blocked, Premium required (`account_error`), benign end-of-queue suppression, generic WebKit audio failure copy.

---

## 9. UI and visual style (for Electron/CSS)

### 9.1 Platform and layout

- **NavigationSplitView**: sidebar (~fixed) + detail; translate to a two-column flex/grid layout.
- **Bottom inset**: now playing bar full width, horizontal padding ~16px, bottom ~10px.
- **Sheets**: login, new playlist; **alerts**: errors, rename playlist; **confirmation dialogs**: delete playlist.

### 9.2 Typography and weight

- Section headers: **title2 semibold** (e.g. “Liked songs”, “Recently played”).
- Secondary copy: **subheadline** + secondary foreground color.
- Navigation title: dynamic (`detailNavigationTitle`).

### 9.3 Color and chrome

- **Accent**: named asset `AccentColor` (Xcode asset catalog) — in Electron, define a single **CSS variable** (e.g. `--accent`) and use for buttons, scrubber, gradients, heart active state.
- **Window background**: system window background (`NSColor.windowBackgroundColor` equivalent).
- **Login backdrop**: layered **radial gradient** from accent (opacity ~0.14 → 0.04 → clear) centered ~(50%, 35%) with radii ~40–420px, plus **linear gradient** fade to window background toward bottom.
- **Hero artwork**: remote images with **dominant-color sampling** (`ArtworkColorSampler`, `HeroArtworkTint`) for tinted headers — port with **canvas** `getImageData` or a small color-thief library.

### 9.4 Components to replicate

- **Track rows**: artwork thumbnail, title, artist (tappable), duration, play affordance, heart, overflow for “add to playlist”.
- **Carousel cards**: larger art, heart overlay corner, tap art for album vs play.
- **Playback bar**: artwork, title/artist, play/pause, next/prev, shuffle, repeat, volume, scrubber, optional lyrics toggle / queue.
- **Mini player**: compact chrome (`MiniPlayerWindowChrome`) — draggable region, traffic lights styling if frameless on macOS.

### 9.5 Motion

- List **remove** animation: snappy ~0.32s (playlist remove).
- Use CSS `transition` / `view transitions` sparingly to match.

---

## 10. Data models (implementation hint)

Spotify DTOs live in `SpotifyModels.swift` (tracks, albums, playlists, search pages, queue, etc.). An Electron TypeScript port should generate or hand-copy interfaces from the same JSON shapes Spotify returns.

---

## 11. Checklist for a faithful Electron port

- [ ] PKCE OAuth with same redirect and scopes; secure token persistence.
- [ ] All **used** REST endpoints from sections 4–5 wired with identical query/body conventions (especially `/me/library`, playlist mutations, `market` / `from_token` behavior).
- [ ] Hidden Web Playback page + **token bridge** + `device_id` capture before `PUT /me/player/play`.
- [ ] Media keys / Now Playing (`navigator.mediaSession`).
- [ ] Genius lyrics pipeline or feature-flagged alternative.
- [ ] Navigation parity: home, library, search, album, artist, playlist CRUD rules, 403 playlist messaging.
- [ ] Visual system: accent, gradients, typography scale, artwork-tinted heroes.

---

## 12. Source map (quick reference)

| Area | Primary files |
|------|----------------|
| REST client | `Lightify/API/SpotifyAPIClient.swift` |
| Player REST | `Lightify/API/SpotifyPlayerAPI.swift` |
| Models | `Lightify/API/SpotifyModels.swift` |
| OAuth / PKCE | `Lightify/Auth/SpotifyAuthService.swift`, `PKCE.swift`, `SpotifyConfig.swift` |
| Session + library | `Lightify/AppState/AppSession.swift` |
| Playback + bridge | `Lightify/Playback/PlaybackViewModel.swift`, `SpotifyWebPlaybackBridge.swift`, `SpotifyPlaybackRESTCoordinator.swift` |
| Web player | `Lightify/WebPlayback/web_player.html`, `web_player.js` |
| Lyrics | `Lightify/Genius/GeniusLyricsService.swift` |
| Dashboard UI | `Lightify/Views/Dashboard/*.swift`, `ContentView.swift` |

This document describes behavior observed in the repository as of the time it was written; Spotify and Genius may change their APIs and terms independently.
