//
//  PlaybackViewModel.swift
//  Lightify
//

import Foundation
import Observation
import WebKit

@MainActor
@Observable
final class PlaybackViewModel {
    /// Matches Spotify Web Playback `repeat_mode` / Web API `state` for repeat.
    enum ConnectRepeatMode: Int, Equatable {
        case off = 0
        case context = 1
        case track = 2

        var webAPIStateValue: String {
            switch self {
            case .off: "off"
            case .context: "context"
            case .track: "track"
            }
        }

        var nextCycled: ConnectRepeatMode {
            switch self {
            case .off: .context
            case .context: .track
            case .track: .off
            }
        }
    }

    struct NowPlaying: Equatable {
        let trackName: String
        let artistName: String
        let albumName: String?
        let durationMs: Int
        var positionMs: Int
        var isPlaying: Bool
        /// Album art from Web Playback SDK when available.
        let artworkURL: URL?
        let uri: String?
        /// Active playback context (`spotify:playlist:…`, etc.) from Web Playback SDK.
        let contextURI: String?
    }

    private let bridge = SpotifyWebPlaybackBridge()
    private let playerAPI = SpotifyPlayerAPI()
    private let apiClient = SpotifyAPIClient()
    private let systemNowPlaying = SystemNowPlayingCoordinator()

    /// Embedded WebKit view hosting the Spotify Web Playback SDK (keep in view hierarchy).
    var webPlayerView: WKWebView { bridge.view }

    var nowPlaying: NowPlaying?
    var playerError: String?

    /// Clears playback-facing alerts (used when the user dismisses the combined playback alert).
    func acknowledgePlaybackIssueAlerts() {
        playerError = nil
        autoplayBlocked = false
        queueError = nil
    }
    var autoplayBlocked: Bool = false
    var playbackVolume: Double = 0.85
    private(set) var webPlayerDeviceId: String?
    private(set) var isWebPlayerReady: Bool = false

    var playbackQueue: [SpotifyTrack] = []
    var queueError: String?
    var isLoadingQueue: Bool = false

    /// When true, the mini player window uses the expanded split layout (player + lyrics). Set by the now playing bar lyrics control.
    var miniPlayerShowsLyricsPanel: Bool = false

    func presentMiniPlayerWithLyricsPanel() {
        miniPlayerShowsLyricsPanel = true
    }

    func dismissMiniPlayerLyricsPanel() {
        miniPlayerShowsLyricsPanel = false
    }

    private weak var appSession: AppSession?
    private var engineStarted = false
    private var sdkStarted = false
    private var progressTickerTask: Task<Void, Never>?
    /// Last raw Web Playback state (for detecting natural track end vs user pause).
    private var lastWebPlaybackPayload: WebPlaybackStatePayload?
    /// The SDK may emit `playback_error` right after a lone track ends; suppress briefly.
    private var suppressBenignPlaybackErrorsUntil: Date?
    /// Last known playback `position` from the SDK (or user seek), aligned with `progressClockAnchorMs`.
    private var progressBasePositionMs = 0
    /// Millisecond clock anchor: SDK `timestamp` when present, otherwise local wall time when the anchor was set.
    private var progressClockAnchorMs: Int64?

    /// Reflects Spotify session shuffle (from Web Playback state; toggled via Web API).
    private(set) var shuffleEnabled: Bool = false
    /// Reflects Spotify repeat mode (from Web Playback state; toggled via Web API).
    private(set) var repeatMode: ConnectRepeatMode = .off

    init() {
        startProgressTicker()
    }

    func attach(appSession: AppSession) {
        self.appSession = appSession
        systemNowPlaying.installRemoteCommands(
            play: { [weak self] in self?.bridge.play() },
            pause: { [weak self] in self?.bridge.pause() },
            togglePlayPause: { [weak self] in self?.playPause() },
            next: { [weak self] in self?.next() },
            previous: { [weak self] in self?.previous() }
        )
        bridge.tokenProvider = { [weak self] in
            guard let self, let session = self.appSession else {
                throw AppSessionError.notSignedIn
            }
            return try await session.validAccessToken()
        }
        bridge.onEvent = { [weak self] event in
            self?.handleBridgeEvent(event)
        }
    }

    /// Loads the bundled player page and connects the SDK once the user is signed in and content is ready.
    func startWebPlaybackEngineIfNeeded() {
        guard !engineStarted else { return }
        guard appSession != nil else { return }
        engineStarted = true
        do {
            try bridge.loadPlayerPage()
        } catch {
            playerError = error.localizedDescription
        }
    }

    /// Clears single-line `playerError` and the no-song alert before a new user-driven playback attempt or when the player becomes ready.
    private func clearPlayerFacingErrors() {
        playerError = nil
        suppressBenignPlaybackErrorsUntil = nil
    }

    func teardownWebPlayback() {
        bridge.disconnect()
        systemNowPlaying.clear()
        engineStarted = false
        sdkStarted = false
        isWebPlayerReady = false
        webPlayerDeviceId = nil
        nowPlaying = nil
        playerError = nil
        autoplayBlocked = false
        playbackVolume = 0.85
        playbackQueue = []
        queueError = nil
        isLoadingQueue = false
        miniPlayerShowsLyricsPanel = false
        progressBasePositionMs = 0
        progressClockAnchorMs = nil
        shuffleEnabled = false
        repeatMode = .off
        lastWebPlaybackPayload = nil
        suppressBenignPlaybackErrorsUntil = nil
    }

    func playTrack(id: String) {
        Task {
            await playTrackAsync(id: id)
        }
    }

    /// True when this track is the current Web Playback item (playing or paused).
    func isNowPlayingTrack(id trackID: String) -> Bool {
        guard let uri = nowPlaying?.uri else { return false }
        return uri == "spotify:track:\(trackID)"
    }

    /// True when this track is current and actively playing (list rows show a pause glyph).
    func isActivePlayingTrack(id trackID: String) -> Bool {
        (nowPlaying?.isPlaying ?? false) && isNowPlayingTrack(id: trackID)
    }

    /// Starts playback in an album, playlist, or artist context (`spotify:album:…`, `spotify:playlist:…`, `spotify:artist:…`).
    func playContextURI(_ uri: String) {
        Task {
            await playContextURIAsync(uri)
        }
    }

    private func playTrackAsync(id: String) async {
        clearPlayerFacingErrors()
        autoplayBlocked = false
        switch await SpotifyPlaybackRESTCoordinator.tokenAndWebDeviceId(
            appSession: appSession,
            webPlayerDeviceId: webPlayerDeviceId
        ) {
        case .failure(let failure):
            playerError = SpotifyPlaybackRESTCoordinator.playerErrorMessage(for: failure)
            return
        case .success(let pair):
            let (token, deviceId) = pair
            bridge.activateElement()
            do {
                try await playerAPI.startPlayback(
                    accessToken: token,
                    deviceId: deviceId,
                    uris: ["spotify:track:\(id)"],
                    contextURI: nil
                )
            } catch {
                playerError = error.localizedDescription
            }
        }
    }

    private func playContextURIAsync(_ uri: String) async {
        clearPlayerFacingErrors()
        autoplayBlocked = false
        switch await SpotifyPlaybackRESTCoordinator.tokenAndWebDeviceId(
            appSession: appSession,
            webPlayerDeviceId: webPlayerDeviceId
        ) {
        case .failure(let failure):
            playerError = SpotifyPlaybackRESTCoordinator.playerErrorMessage(for: failure)
            return
        case .success(let pair):
            let (token, deviceId) = pair
            bridge.activateElement()
            do {
                try await playerAPI.startPlayback(
                    accessToken: token,
                    deviceId: deviceId,
                    uris: nil,
                    contextURI: uri,
                    positionMs: nil
                )
            } catch {
                playerError = error.localizedDescription
            }
        }
    }

    /// Plays tracks in order (e.g. Liked Songs). Spotify accepts a bounded list of `uris` per request.
    func playTrackList(trackIDs: [String]) {
        Task {
            await playTrackListAsync(trackIDs: trackIDs)
        }
    }

    private func playTrackListAsync(trackIDs: [String]) async {
        guard !trackIDs.isEmpty else { return }
        clearPlayerFacingErrors()
        autoplayBlocked = false
        switch await SpotifyPlaybackRESTCoordinator.tokenAndWebDeviceId(
            appSession: appSession,
            webPlayerDeviceId: webPlayerDeviceId
        ) {
        case .failure(let failure):
            playerError = SpotifyPlaybackRESTCoordinator.playerErrorMessage(for: failure)
            return
        case .success(let pair):
            let (token, deviceId) = pair
            bridge.activateElement()
            // Web API accepts a limited number of track URIs per `PUT /me/player/play` body.
            let capped = Array(trackIDs.prefix(Self.maxTrackURIsPerPlayRequest))
            let uris = capped.map { "spotify:track:\($0)" }
            do {
                try await playerAPI.startPlayback(
                    accessToken: token,
                    deviceId: deviceId,
                    uris: uris,
                    contextURI: nil,
                    positionMs: nil
                )
            } catch {
                playerError = error.localizedDescription
            }
        }
    }

    private static let maxTrackURIsPerPlayRequest = 100

    func playPause() {
        bridge.togglePlay()
    }

    func next() {
        bridge.nextTrack()
    }

    func previous() {
        bridge.previousTrack()
    }

    func setPlaybackVolume(_ value: Double) {
        guard isWebPlayerReady else { return }
        let clamped = min(max(value, 0), 1)
        playbackVolume = clamped
        bridge.setVolume(clamped)
    }

    func seek(to positionMs: Int) {
        guard isWebPlayerReady else { return }
        guard var nowPlaying, nowPlaying.durationMs > 0 else { return }
        let clamped = min(max(positionMs, 0), nowPlaying.durationMs)
        nowPlaying.positionMs = clamped
        self.nowPlaying = nowPlaying
        progressBasePositionMs = clamped
        progressClockAnchorMs = nowPlaying.isPlaying ? Self.epochWallMs() : nil
        bridge.seek(to: clamped)
    }

    func setShuffleEnabled(_ enabled: Bool) {
        Task {
            await setShuffleEnabledAsync(enabled)
        }
    }

    func cycleRepeatMode() {
        Task {
            await cycleRepeatModeAsync()
        }
    }

    private func setShuffleEnabledAsync(_ enabled: Bool) async {
        clearPlayerFacingErrors()
        switch await SpotifyPlaybackRESTCoordinator.tokenAndWebDeviceId(
            appSession: appSession,
            webPlayerDeviceId: webPlayerDeviceId
        ) {
        case .failure(let failure):
            playerError = SpotifyPlaybackRESTCoordinator.playerErrorMessage(for: failure)
            return
        case .success(let pair):
            let (token, deviceId) = pair
            do {
                try await playerAPI.setShuffleState(accessToken: token, enabled: enabled, deviceId: deviceId)
            } catch {
                playerError = error.localizedDescription
            }
        }
    }

    private func cycleRepeatModeAsync() async {
        clearPlayerFacingErrors()
        switch await SpotifyPlaybackRESTCoordinator.tokenAndWebDeviceId(
            appSession: appSession,
            webPlayerDeviceId: webPlayerDeviceId
        ) {
        case .failure(let failure):
            playerError = SpotifyPlaybackRESTCoordinator.playerErrorMessage(for: failure)
            return
        case .success(let pair):
            let (token, deviceId) = pair
            let next = repeatMode.nextCycled
            do {
                try await playerAPI.setRepeatMode(accessToken: token, state: next.webAPIStateValue, deviceId: deviceId)
            } catch {
                playerError = error.localizedDescription
            }
        }
    }

    func refreshPlaybackQueue() async {
        queueError = nil
        guard let appSession else {
            queueError = AppSessionError.notSignedIn.localizedDescription
            return
        }
        isLoadingQueue = true
        defer { isLoadingQueue = false }
        do {
            let token = try await appSession.validAccessToken()
            let response = try await apiClient.fetchPlaybackQueue(accessToken: token)
            playbackQueue = response.queue
            queueError = nil
        } catch {
            queueError = error.localizedDescription
            playbackQueue = []
        }
    }

    /// Spotify sometimes reports the literal string “Playback error” when WebKit fails to take a
    /// “WebKit Media Playback” RunningBoard assertion — third-party apps cannot add the internal
    /// `com.apple.runningboard.assertions.webkit` entitlement; Console noise may not mean a user bug.
    private static let genericWebKitSpotifyPlaybackFailure =
        "The embedded Spotify player lost audio. This is often a temporary macOS / WebKit issue. Try pressing play again, or quit and reopen Lightify."

    private static func userFacingPlaybackSDKErrorMessage(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return genericWebKitSpotifyPlaybackFailure }
        if trimmed.caseInsensitiveCompare("playback error") == .orderedSame {
            return genericWebKitSpotifyPlaybackFailure
        }
        return raw
    }

    /// Messages Spotify’s Web Playback SDK emits when there is nothing to advance to (e.g. single track finished, empty `next_tracks`).
    /// These are not user-actionable failures; surfacing them as “Playback” errors is misleading.
    private static func isBenignEmptyQueueOrEndOfPlaybackSDKMessage(_ message: String) -> Bool {
        let lower = message.lowercased()
        if lower.contains("no list was loaded") { return true }
        if lower.contains("cannot perform") || lower.contains("can not perform") {
            if lower.contains("action") || lower.contains("operation") { return true }
        }
        if lower.contains("cannot skip") { return true }
        if lower.contains("can not skip") { return true }
        if lower.contains("nothing to skip") { return true }
        return false
    }

    private func notePossibleNaturalTrackEnd(from previous: WebPlaybackStatePayload?, to incoming: WebPlaybackStatePayload) {
        guard let prev = previous,
              let trackURI = incoming.currentTrack?.uri,
              prev.currentTrack?.uri == trackURI,
              !prev.paused,
              incoming.paused,
              incoming.repeatModeRaw == 0,
              incoming.nextTracksCount == 0,
              incoming.duration > 0
        else { return }

        let nearEnd = incoming.position >= max(incoming.duration - 3_000, 0)
        // Some SDK versions emit a follow-up state with `position == 0` after a near-complete play (see spotify/web-playback-sdk#85).
        let pausedAtZeroAfterNearComplete =
            incoming.position == 0
            && prev.position >= max(prev.duration - 3_000, 0)
            && prev.position > 0
        if nearEnd || pausedAtZeroAfterNearComplete {
            suppressBenignPlaybackErrorsUntil = Date().addingTimeInterval(5)
        }
    }

    private func handleBridgeEvent(_ event: SpotifyWebPlaybackBridge.BridgeEvent) {
        switch event {
        case .sdkReady:
            guard !sdkStarted else { return }
            sdkStarted = true
            bridge.startPlayer()
        case let .connectResult(success):
            if !success {
                playerError = "Could not connect Spotify Web Playback."
            }
        case let .ready(deviceId):
            webPlayerDeviceId = deviceId
            isWebPlayerReady = true
            clearPlayerFacingErrors()
        case .notReady:
            isWebPlayerReady = false
        case let .playerStateChanged(payload):
            if let incoming = payload {
                notePossibleNaturalTrackEnd(from: lastWebPlaybackPayload, to: incoming)
            }
            if let payload {
                playbackVolume = payload.volume
                shuffleEnabled = payload.shuffle
                repeatMode = ConnectRepeatMode(rawValue: payload.repeatModeRaw) ?? .off
                if let track = payload.currentTrack {
                    let durationMs = max(payload.duration, 0)
                    let positionMs = min(max(payload.position, 0), durationMs)
                    nowPlaying = NowPlaying(
                        trackName: track.name,
                        artistName: track.artistNames,
                        albumName: track.albumName,
                        durationMs: durationMs,
                        positionMs: positionMs,
                        isPlaying: !payload.paused,
                        artworkURL: track.artworkURL,
                        uri: track.uri,
                        contextURI: payload.contextURI
                    )
                    progressBasePositionMs = positionMs
                    let canExtrapolateProgress =
                        !payload.paused
                        && track.isPlayable
                        && durationMs > 0
                    if canExtrapolateProgress {
                        progressClockAnchorMs = payload.timestampMs ?? Self.epochWallMs()
                    } else {
                        progressClockAnchorMs = nil
                    }
                    systemNowPlaying.update(
                        snapshot: .init(
                            trackURI: track.uri,
                            title: track.name,
                            artist: track.artistNames,
                            album: track.albumName,
                            durationMs: durationMs,
                            positionMs: positionMs,
                            isPlaying: !payload.paused,
                            artworkURL: track.artworkURL
                        )
                    )
                } else {
                    nowPlaying = nil
                    progressBasePositionMs = 0
                    progressClockAnchorMs = nil
                    shuffleEnabled = false
                    repeatMode = .off
                    systemNowPlaying.clear()
                }
            } else {
                nowPlaying = nil
                progressBasePositionMs = 0
                progressClockAnchorMs = nil
                shuffleEnabled = false
                repeatMode = .off
                systemNowPlaying.clear()
            }
            lastWebPlaybackPayload = payload
        case .autoplayFailed:
            autoplayBlocked = true
            playerError = "Playback was blocked by the browser. Try play/pause or pick a track again."
        case let .initializationError(msg),
             let .authenticationError(msg):
            playerError = msg
        case let .playbackError(msg):
            let nearEndedUI: Bool = {
                guard let np = nowPlaying, !np.isPlaying, np.durationMs > 0, repeatMode == .off else { return false }
                return np.positionMs >= np.durationMs - 3_000
            }()
            let benign = Self.isBenignEmptyQueueOrEndOfPlaybackSDKMessage(msg)
                || (suppressBenignPlaybackErrorsUntil.map { Date() < $0 } ?? false)
                || nearEndedUI
            if benign {
                playerError = nil
            } else {
                playerError = Self.userFacingPlaybackSDKErrorMessage(msg)
            }
        case let .accountError(msg):
            playerError = "Spotify Premium is required for Web Playback: \(msg)"
        case .log:
            break
        }
    }

    /// How often the progress ticker runs while playing (drives `positionMs` for UI such as the scrubber).
    static let progressTickerIntervalMs: UInt64 = 250

    private func startProgressTicker() {
        progressTickerTask?.cancel()
        progressTickerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(Self.progressTickerIntervalMs))
                guard let self, !Task.isCancelled else { break }
                await MainActor.run {
                    self.refreshProgress()
                }
            }
        }
    }

    private func refreshProgress() {
        guard var nowPlaying else { return }
        guard nowPlaying.isPlaying, nowPlaying.durationMs > 0 else { return }
        guard let anchor = progressClockAnchorMs else { return }

        let nowMs = Self.epochWallMs()
        let extrapolated = progressBasePositionMs + Int(nowMs - anchor)
        let updatedPositionMs = min(max(extrapolated, 0), nowPlaying.durationMs)
        guard updatedPositionMs != nowPlaying.positionMs else { return }

        nowPlaying.positionMs = updatedPositionMs
        self.nowPlaying = nowPlaying
    }

    private static func epochWallMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

}
