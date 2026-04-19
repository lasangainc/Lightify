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
    /// Shown as its own alert (title + message) when the SDK has nothing to play.
    private(set) var noSongQueuedPlaybackAlert: (title: String, message: String)?

    /// Clears playback-facing alerts (used when the user dismisses the combined playback alert).
    func acknowledgePlaybackIssueAlerts() {
        noSongQueuedPlaybackAlert = nil
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
    private var progressReferencePositionMs = 0
    private var progressReferenceDate: Date?

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
            noSongQueuedPlaybackAlert = nil
            playerError = error.localizedDescription
        }
    }

    /// Clears single-line `playerError` and the no-song alert before a new user-driven playback attempt or when the player becomes ready.
    private func clearPlayerFacingErrors() {
        playerError = nil
        noSongQueuedPlaybackAlert = nil
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
        noSongQueuedPlaybackAlert = nil
        autoplayBlocked = false
        playbackVolume = 0.85
        playbackQueue = []
        queueError = nil
        isLoadingQueue = false
        miniPlayerShowsLyricsPanel = false
        progressReferencePositionMs = 0
        progressReferenceDate = nil
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
        guard let appSession else {
            playerError = AppSessionError.notSignedIn.localizedDescription
            return
        }
        guard let deviceId = webPlayerDeviceId else {
            playerError = "Player is not ready yet. Wait a moment and try again."
            return
        }
        bridge.activateElement()
        do {
            let token = try await appSession.validAccessToken()
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

    private func playContextURIAsync(_ uri: String) async {
        clearPlayerFacingErrors()
        autoplayBlocked = false
        guard let appSession else {
            playerError = AppSessionError.notSignedIn.localizedDescription
            return
        }
        guard let deviceId = webPlayerDeviceId else {
            playerError = "Player is not ready yet. Wait a moment and try again."
            return
        }
        bridge.activateElement()
        do {
            let token = try await appSession.validAccessToken()
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
        guard let appSession else {
            playerError = AppSessionError.notSignedIn.localizedDescription
            return
        }
        guard let deviceId = webPlayerDeviceId else {
            playerError = "Player is not ready yet. Wait a moment and try again."
            return
        }
        bridge.activateElement()
        // Web API accepts a limited number of track URIs per `PUT /me/player/play` body.
        let capped = Array(trackIDs.prefix(Self.maxTrackURIsPerPlayRequest))
        let uris = capped.map { "spotify:track:\($0)" }
        do {
            let token = try await appSession.validAccessToken()
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
        progressReferencePositionMs = clamped
        progressReferenceDate = nowPlaying.isPlaying ? Date() : nil
        bridge.seek(to: clamped)
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

    private static let noSongQueuedAlertTitle = "No song to play!"
    private static let noSongQueuedAlertMessage = "Please select a song"

    /// Spotify’s Web Playback SDK uses several wordings (e.g. “…Action” vs “…operation; no list was loaded.”).
    private static func shouldPresentNoSongQueuedAlert(forPlaybackSDKMessage message: String) -> Bool {
        let lower = message.lowercased()
        if lower.contains("no list was loaded") { return true }
        if lower.contains("cannot perform") || lower.contains("can not perform") {
            return lower.contains("action") || lower.contains("operation")
        }
        return false
    }

    private func handleBridgeEvent(_ event: SpotifyWebPlaybackBridge.BridgeEvent) {
        switch event {
        case .sdkReady:
            guard !sdkStarted else { return }
            sdkStarted = true
            bridge.startPlayer()
        case let .connectResult(success):
            if !success {
                noSongQueuedPlaybackAlert = nil
                playerError = "Could not connect Spotify Web Playback."
            }
        case let .ready(deviceId):
            webPlayerDeviceId = deviceId
            isWebPlayerReady = true
            clearPlayerFacingErrors()
        case .notReady:
            isWebPlayerReady = false
        case let .playerStateChanged(payload):
            if let payload {
                playbackVolume = payload.volume
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
                    progressReferencePositionMs = positionMs
                    progressReferenceDate = payload.paused ? nil : Date()
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
                    progressReferencePositionMs = 0
                    progressReferenceDate = nil
                    systemNowPlaying.clear()
                }
            } else {
                nowPlaying = nil
                progressReferencePositionMs = 0
                progressReferenceDate = nil
                systemNowPlaying.clear()
            }
        case .autoplayFailed:
            autoplayBlocked = true
            noSongQueuedPlaybackAlert = nil
            playerError = "Playback was blocked by the browser. Try play/pause or pick a track again."
        case let .initializationError(msg),
             let .authenticationError(msg):
            noSongQueuedPlaybackAlert = nil
            playerError = msg
        case let .playbackError(msg):
            if Self.shouldPresentNoSongQueuedAlert(forPlaybackSDKMessage: msg) {
                noSongQueuedPlaybackAlert = (Self.noSongQueuedAlertTitle, Self.noSongQueuedAlertMessage)
                playerError = nil
            } else {
                noSongQueuedPlaybackAlert = nil
                playerError = msg
            }
        case let .accountError(msg):
            noSongQueuedPlaybackAlert = nil
            playerError = "Spotify Premium is required for Web Playback: \(msg)"
        case .log:
            break
        }
    }

    private func startProgressTicker() {
        progressTickerTask?.cancel()
        progressTickerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
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
        guard let progressReferenceDate else { return }

        let elapsedMs = max(0, Int(Date().timeIntervalSince(progressReferenceDate) * 1000))
        let updatedPositionMs = min(nowPlaying.durationMs, progressReferencePositionMs + elapsedMs)
        guard updatedPositionMs != nowPlaying.positionMs else { return }

        nowPlaying.positionMs = updatedPositionMs
        self.nowPlaying = nowPlaying
    }

}
