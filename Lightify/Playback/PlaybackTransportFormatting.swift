//
//  PlaybackTransportFormatting.swift
//  Lightify
//

import SwiftUI

enum PlaybackTransportFormatting {
    static func repeatSymbolName(for repeatMode: PlaybackViewModel.ConnectRepeatMode) -> String {
        switch repeatMode {
        case .off, .context: "repeat"
        case .track: "repeat.1"
        }
    }

    static func repeatHelp(for repeatMode: PlaybackViewModel.ConnectRepeatMode) -> String {
        switch repeatMode {
        case .off:
            "Repeat: off (tap for context)"
        case .context:
            "Repeat: playlist or album (tap for one track)"
        case .track:
            "Repeat: one track (tap to turn off)"
        }
    }

    static func volumeSpeakerSymbolName(playbackVolume: Double) -> String {
        let v = playbackVolume
        if v <= 0.001 { return "speaker.slash.fill" }
        if v < 0.34 { return "speaker.wave.1.fill" }
        if v < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}

enum PlaybackTransportAnimations {
    /// Layered replace when play ↔ pause changes (mini player + now playing bar).
    static let playPauseSymbolReplace = Animation.spring(response: 0.16, dampingFraction: 0.52)
}

extension View {
    func islandPlayPauseSymbolReplace<V: Equatable>(value: V, animation: Animation? = nil) -> some View {
        let resolved = animation ?? PlaybackTransportAnimations.playPauseSymbolReplace
        return self
            .contentTransition(.symbolEffect(.replace.offUp.byLayer, options: .nonRepeating))
            .animation(resolved, value: value)
    }
}
