//
//  SpotifyWebPlaybackBridge.swift
//  Lightify
//

import Foundation
import WebKit

/// Hosts the Spotify Web Playback SDK in a `WKWebView` and bridges events/commands to Swift.
@MainActor
final class SpotifyWebPlaybackBridge: NSObject {
    enum BridgeEvent: Equatable {
        case sdkReady
        case connectResult(success: Bool)
        case ready(deviceId: String)
        case notReady(deviceId: String)
        case playerStateChanged(WebPlaybackStatePayload?)
        case autoplayFailed
        case initializationError(String)
        case authenticationError(String)
        case accountError(String)
        case playbackError(String)
        case log(String)
    }

    private let webView: WKWebView
    private let userContentController: WKUserContentController
    private let messageHandlerName = "lightifySpotify"

    var onEvent: (@MainActor (BridgeEvent) -> Void)?

    /// Provides a fresh access token when the SDK requests one (including refresh).
    var tokenProvider: (@MainActor () async throws -> String)?

    override init() {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        if #available(macOS 11.0, *) {
            config.defaultWebpagePreferences.allowsContentJavaScript = true
        }
        userContentController = config.userContentController
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        userContentController.add(self, name: messageHandlerName)
        webView.navigationDelegate = self
        webView.isInspectable = true
    }

    var view: WKWebView { webView }

    func loadPlayerPage() throws {
        // Folder-synced targets often copy resources flat into `Contents/Resources/` (no `WebPlayback/` subfolder).
        let htmlURL =
            Bundle.main.url(forResource: "web_player", withExtension: "html", subdirectory: "WebPlayback")
            ?? Bundle.main.url(forResource: "web_player", withExtension: "html")
        guard let htmlURL else {
            throw SpotifyWebPlaybackError.missingBundleResource
        }
        webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
    }

    func startPlayer() {
        evaluate("window.lightifyStartPlayer && window.lightifyStartPlayer()")
    }

    func deliverToken(_ token: String) {
        let escaped = token.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        evaluate("window.lightifyDeliverToken && window.lightifyDeliverToken('\(escaped)')")
    }

    func activateElement() {
        evaluate("window.lightifyActivateElement && window.lightifyActivateElement()")
    }

    func togglePlay() {
        evaluate("window.lightifyTogglePlay && window.lightifyTogglePlay()")
    }

    func play() {
        evaluate("window.lightifyPlay && window.lightifyPlay()")
    }

    func pause() {
        evaluate("window.lightifyPause && window.lightifyPause()")
    }

    func nextTrack() {
        evaluate("window.lightifyNext && window.lightifyNext()")
    }

    func previousTrack() {
        evaluate("window.lightifyPrevious && window.lightifyPrevious()")
    }

    func disconnect() {
        evaluate("window.lightifyDisconnect && window.lightifyDisconnect()")
    }

    func setVolume(_ normalized: Double) {
        let clamped = min(max(normalized, 0), 1)
        let encoded = String(clamped)
        evaluate("window.lightifySetVolume && window.lightifySetVolume(\(encoded))")
    }

    func seek(to positionMs: Int) {
        let clamped = max(positionMs, 0)
        evaluate("window.lightifySeek && window.lightifySeek(\(clamped))")
    }

    private func evaluate(_ js: String) {
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func handleMessageBody(_ body: Any) {
        guard let str = body as? String,
              let data = str.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String
        else {
            return
        }

        switch type {
        case "sdk_ready":
            onEvent?(.sdkReady)
        case "connect_result":
            let ok = json["success"] as? Bool ?? false
            onEvent?(.connectResult(success: ok))
        case "ready":
            if let id = json["device_id"] as? String {
                onEvent?(.ready(deviceId: id))
            }
        case "not_ready":
            if let id = json["device_id"] as? String {
                onEvent?(.notReady(deviceId: id))
            }
        case "player_state_changed":
            if json["state"] is NSNull || json["state"] == nil {
                onEvent?(.playerStateChanged(nil))
            } else if let stateObj = json["state"] as? [String: Any] {
                let payload = WebPlaybackStatePayload(dictionary: stateObj)
                onEvent?(.playerStateChanged(payload))
            }
        case "autoplay_failed":
            onEvent?(.autoplayFailed)
        case "initialization_error":
            onEvent?(.initializationError(json["message"] as? String ?? "unknown"))
        case "authentication_error":
            onEvent?(.authenticationError(json["message"] as? String ?? "unknown"))
        case "account_error":
            onEvent?(.accountError(json["message"] as? String ?? "unknown"))
        case "playback_error":
            onEvent?(.playbackError(json["message"] as? String ?? "unknown"))
        case "need_token":
            Task { await fulfillTokenRequest() }
        case "log":
            onEvent?(.log(json["message"] as? String ?? ""))
        default:
            break
        }
    }

    private func fulfillTokenRequest() async {
        guard let provider = tokenProvider else {
            deliverToken("")
            return
        }
        do {
            let token = try await provider()
            deliverToken(token)
        } catch {
            deliverToken("")
            onEvent?(.authenticationError(error.localizedDescription))
        }
    }
}

extension SpotifyWebPlaybackBridge: WKScriptMessageHandler {
    nonisolated func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        Task { @MainActor in
            self.handleMessageBody(message.body)
        }
    }
}

extension SpotifyWebPlaybackBridge: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onEvent?(.initializationError(error.localizedDescription))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        onEvent?(.initializationError(error.localizedDescription))
    }
}

enum SpotifyWebPlaybackError: LocalizedError {
    case missingBundleResource

    var errorDescription: String? {
        switch self {
        case .missingBundleResource:
            return "Web player resources are missing from the app bundle. Ensure `web_player.html` and `web_player.js` are in the Lightify target (Copy Bundle Resources)."
        }
    }
}
