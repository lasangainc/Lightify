//
//  PlaybackIssueAlerts.swift
//  Lightify
//

import SwiftUI

/// Surfaces player, autoplay, and queue issues in a standard alert instead of inline banners.
private struct PlaybackIssueAlertsModifier: ViewModifier {
    @Environment(PlaybackViewModel.self) private var playback

    private var alertTitle: String {
        if let noSong = playback.noSongQueuedPlaybackAlert {
            return noSong.title
        }
        return "Playback"
    }

    private var alertMessage: String {
        if let noSong = playback.noSongQueuedPlaybackAlert {
            return noSong.message
        }
        if let e = playback.playerError { return e }
        if playback.autoplayBlocked {
            return "Autoplay blocked — tap play or pick a track"
        }
        if let q = playback.queueError { return q }
        return ""
    }

    private var alertPresented: Binding<Bool> {
        Binding(
            get: {
                playback.noSongQueuedPlaybackAlert != nil
                    || playback.playerError != nil
                    || playback.autoplayBlocked
                    || playback.queueError != nil
            },
            set: { newValue in
                guard !newValue else { return }
                playback.acknowledgePlaybackIssueAlerts()
            }
        )
    }

    func body(content: Content) -> some View {
        content
            .alert(alertTitle, isPresented: alertPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
    }
}

extension View {
    func playbackIssueAlerts() -> some View {
        modifier(PlaybackIssueAlertsModifier())
    }
}
