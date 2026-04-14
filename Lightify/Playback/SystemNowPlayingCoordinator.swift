//
//  SystemNowPlayingCoordinator.swift
//  Lightify
//

import AppKit
import Foundation
import MediaPlayer

/// Publishes playback metadata to macOS Control Center / menu bar Now Playing.
@MainActor
final class SystemNowPlayingCoordinator {
    struct Snapshot: Equatable {
        let trackURI: String?
        let title: String
        let artist: String
        let album: String?
        let durationMs: Int
        let positionMs: Int
        let isPlaying: Bool
        let artworkURL: URL?
    }

    private var activeTrackURI: String?
    private var pendingArtworkTask: Task<Void, Never>?
    private var remoteCommandsConfigured = false

    func update(snapshot: Snapshot) {
        activeTrackURI = snapshot.trackURI
        pendingArtworkTask?.cancel()
        pendingArtworkTask = nil

        let info = Self.makeNowPlayingInfo(from: snapshot, artwork: nil)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        guard let url = snapshot.artworkURL else { return }

        let expectedURI = snapshot.trackURI
        pendingArtworkTask = Task { [weak self] in
            let image = await Self.downloadArtwork(from: url)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                guard self.activeTrackURI == expectedURI else { return }
                let merged = Self.makeNowPlayingInfo(from: snapshot, artwork: image)
                MPNowPlayingInfoCenter.default().nowPlayingInfo = merged
            }
        }
    }

    func clear() {
        activeTrackURI = nil
        pendingArtworkTask?.cancel()
        pendingArtworkTask = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    /// Wire hardware / Control Center transport to the embedded player.
    func installRemoteCommands(
        play: @escaping () -> Void,
        pause: @escaping () -> Void,
        togglePlayPause: @escaping () -> Void,
        next: @escaping () -> Void,
        previous: @escaping () -> Void
    ) {
        guard !remoteCommandsConfigured else { return }
        remoteCommandsConfigured = true

        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true

        center.playCommand.addTarget { _ in
            play()
            return .success
        }
        center.pauseCommand.addTarget { _ in
            pause()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { _ in
            togglePlayPause()
            return .success
        }
        center.nextTrackCommand.addTarget { _ in
            next()
            return .success
        }
        center.previousTrackCommand.addTarget { _ in
            previous()
            return .success
        }
    }

    private static func makeNowPlayingInfo(from snapshot: Snapshot, artwork: NSImage?) -> [String: Any] {
        let durationSec = max(0, Double(snapshot.durationMs) / 1000.0)
        let positionSec = max(0, Double(snapshot.positionMs) / 1000.0)
        let rate = snapshot.isPlaying ? 1.0 : 0.0

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: snapshot.title,
            MPMediaItemPropertyArtist: snapshot.artist,
            MPMediaItemPropertyPlaybackDuration: durationSec,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: positionSec,
            MPNowPlayingInfoPropertyPlaybackRate: rate,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
        ]
        if let album = snapshot.album, !album.isEmpty {
            info[MPMediaItemPropertyAlbumTitle] = album
        }
        if let image = artwork {
            let art = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            info[MPMediaItemPropertyArtwork] = art
        }
        return info
    }

    private nonisolated static func downloadArtwork(from url: URL) async -> NSImage? {
        do {
            return try await ArtworkPipeline.shared.image(for: url, maxPixelSize: 512)
        } catch {
            return nil
        }
    }
}
