//
//  SpotifyPlaybackRESTCoordinator.swift
//  Lightify
//

import Foundation

/// Shared “valid token + Web Playback device id” prep for `SpotifyPlayerAPI` player endpoints.
enum SpotifyPlaybackRESTCoordinator {
    enum PrepFailure: Error, Equatable {
        case notSignedIn
        case playerNotReady
        case tokenError(String)
    }

    /// Returns `(accessToken, deviceId)` for calls that require a non-nil `device_id`.
    static func tokenAndWebDeviceId(
        appSession: AppSession?,
        isWebPlayerReady: Bool,
        webPlayerDeviceId: String?
    ) async -> Result<(String, String), PrepFailure> {
        guard let appSession else { return .failure(.notSignedIn) }
        guard isWebPlayerReady else { return .failure(.playerNotReady) }
        guard let deviceId = webPlayerDeviceId, !deviceId.isEmpty else {
            return .failure(.playerNotReady)
        }
        do {
            let token = try await appSession.validAccessToken()
            return .success((token, deviceId))
        } catch {
            return .failure(.tokenError(error.localizedDescription))
        }
    }

    static func playerErrorMessage(for failure: PrepFailure) -> String {
        switch failure {
        case .notSignedIn:
            AppSessionError.notSignedIn.localizedDescription
        case .playerNotReady:
            "Player is not ready yet. Wait a moment and try again."
        case .tokenError(let message):
            message
        }
    }
}
