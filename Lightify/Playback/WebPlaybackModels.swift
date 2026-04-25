//
//  WebPlaybackModels.swift
//  Lightify
//

import Foundation

/// Subset of Spotify Web Playback SDK `player_state_changed` payload for UI.
struct WebPlaybackStatePayload: Equatable {
    let paused: Bool
    let position: Int
    let duration: Int
    let volume: Double
    /// Milliseconds since Unix epoch when `position` was sampled (drives accurate progress between events).
    let timestampMs: Int64?
    /// `repeat_mode` from the SDK: 0 = off, 1 = context, 2 = track.
    let repeatModeRaw: Int
    let shuffle: Bool
    /// From `context.uri` when playing in an album, playlist, or artist context.
    let contextURI: String?
    /// Count of `track_window.next_tracks` (Spotify may try to advance when this is 0 and emit a benign `playback_error`).
    let nextTracksCount: Int
    let currentTrack: WebPlaybackTrackPayload?

    init(dictionary: [String: Any]) {
        let paused = dictionary["paused"] as? Bool ?? true
        let position: Int = Self.intValue(dictionary["position"])
        let duration: Int = Self.intValue(dictionary["duration"])
        let volume = Self.doubleValue(dictionary["volume"], default: 0.85)
        let timestampMs = Self.int64Value(dictionary["timestamp"])
        let repeatModeRaw = Self.intValue(dictionary["repeat_mode"])
        let shuffle = dictionary["shuffle"] as? Bool ?? false
        let contextURI = (dictionary["context"] as? [String: Any])?["uri"] as? String
        var track: WebPlaybackTrackPayload?
        var nextTracksCount = 0
        if let tw = dictionary["track_window"] as? [String: Any] {
            if let ct = tw["current_track"] as? [String: Any],
               let parsed = WebPlaybackTrackPayload(dictionary: ct)
            {
                track = parsed
            }
            if let next = tw["next_tracks"] as? [Any] {
                nextTracksCount = next.count
            }
        }
        self.paused = paused
        self.position = position
        self.duration = duration
        self.volume = volume
        self.timestampMs = timestampMs
        self.repeatModeRaw = repeatModeRaw
        self.shuffle = shuffle
        self.contextURI = contextURI
        self.nextTracksCount = nextTracksCount
        self.currentTrack = track
    }

    private static func doubleValue(_ any: Any?, default defaultValue: Double) -> Double {
        switch any {
        case let d as Double:
            return min(max(d, 0), 1)
        case let f as Float:
            return min(max(Double(f), 0), 1)
        case let i as Int:
            return min(max(Double(i), 0), 1)
        case let n as NSNumber:
            return min(max(n.doubleValue, 0), 1)
        default:
            return defaultValue
        }
    }

    private static func intValue(_ any: Any?) -> Int {
        switch any {
        case let i as Int:
            return i
        case let d as Double:
            return Int(d)
        case let n as NSNumber:
            return n.intValue
        default:
            return 0
        }
    }

    private static func int64Value(_ any: Any?) -> Int64? {
        switch any {
        case let i as Int:
            return Int64(i)
        case let i64 as Int64:
            return i64
        case let d as Double:
            return Int64(d)
        case let n as NSNumber:
            return n.int64Value
        default:
            return nil
        }
    }
}

struct WebPlaybackTrackPayload: Equatable {
    let name: String
    let artistNames: String
    let albumName: String?
    /// Best-effort album cover from Web Playback `album.images` (largest width).
    let artworkURL: URL?
    let uri: String?
    let isPlayable: Bool

    /// `spotify:track:…` id for REST fallback when `artworkURL` is missing.
    var spotifyTrackId: String? {
        guard let uri else { return nil }
        let prefix = "spotify:track:"
        guard uri.hasPrefix(prefix) else { return nil }
        return String(uri.dropFirst(prefix.count))
    }

    init?(dictionary: [String: Any]) {
        let name = dictionary["name"] as? String ?? ""
        let uri = dictionary["uri"] as? String
        if name.isEmpty && uri == nil {
            return nil
        }
        var artists: [String] = []
        if let arr = dictionary["artists"] as? [[String: Any]] {
            for a in arr {
                if let n = a["name"] as? String {
                    artists.append(n)
                }
            }
        }
        let albumDict = dictionary["album"] as? [String: Any]
        let albumName = albumDict?["name"] as? String
        let artworkURL = Self.bestArtworkURL(from: albumDict)
        let isPlayable = dictionary["is_playable"] as? Bool ?? true
        self.name = name
        self.artistNames = artists.joined(separator: ", ")
        self.albumName = albumName
        self.artworkURL = artworkURL
        self.uri = uri
        self.isPlayable = isPlayable
    }

    private static func bestArtworkURL(from album: [String: Any]?) -> URL? {
        guard let album else { return nil }
        guard let images = album["images"] as? [[String: Any]], !images.isEmpty else { return nil }
        let sorted = images.sorted { a, b in
            let wa = (a["width"] as? Int) ?? 0
            let wb = (b["width"] as? Int) ?? 0
            return wa > wb
        }
        for img in sorted {
            if let s = img["url"] as? String, let url = URL(string: s) {
                return url
            }
        }
        return nil
    }
}
