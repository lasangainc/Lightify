//
//  LibrarySection.swift
//  Lightify
//

import AppKit
import SwiftUI

// MARK: - Hero tint (light mode)

/// Semantic system colors used for light-mode hero gradients (closest-hue match to artwork).
private let systemHeroCandidateColors: [NSColor] = [
    .systemRed, .systemOrange, .systemYellow, .systemGreen,
    .systemMint, .systemTeal, .systemCyan, .systemBlue,
    .systemIndigo, .systemPurple, .systemPink
]

/// Darkened RGB stop matching `ArtworkColorSampler`’s `averageDark` scale (0.58).
private func heroDarkenedGradientEnd(from nsColor: NSColor) -> Color {
    let rgb = nsColor.usingColorSpace(.deviceRGB) ?? nsColor
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 0
    rgb.getRed(&r, green: &g, blue: &b, alpha: &a)
    let darkScale: CGFloat = 0.58
    return Color(
        red: min(max(r * darkScale, 0), 1),
        green: min(max(g * darkScale, 0), 1),
        blue: min(max(b * darkScale, 0), 1),
        opacity: a
    )
}

private func nearestSystemHeroStops(from palette: ArtworkPalette) -> (color: Color, gradientEnd: Color) {
    let reference = palette.vibrant?.color ?? palette.average
    let ns = NSColor(reference)
    let rgb = ns.usingColorSpace(.deviceRGB) ?? ns
    var h: CGFloat = 0
    var s: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 0
    rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
    if s < 0.12 {
        let gray = NSColor.systemGray
        return (Color(nsColor: gray), heroDarkenedGradientEnd(from: gray))
    }
    var best = NSColor.systemBlue
    var bestHueDist = CGFloat.greatestFiniteMagnitude
    for candidate in systemHeroCandidateColors {
        let cRGB = candidate.usingColorSpace(.deviceRGB) ?? candidate
        var ch: CGFloat = 0
        var cs: CGFloat = 0
        var cb: CGFloat = 0
        var ca: CGFloat = 0
        cRGB.getHue(&ch, saturation: &cs, brightness: &cb, alpha: &ca)
        let delta = abs(h - ch)
        let hueDist = min(delta, 1 - delta)
        if hueDist < bestHueDist {
            bestHueDist = hueDist
            best = candidate
        }
    }
    return (Color(nsColor: best), heroDarkenedGradientEnd(from: best))
}

// MARK: - Hero layout (cover)

private enum LibraryHeroLayout {
    static let coverSide: CGFloat = 140
    static let contentPadding: CGFloat = 20
}

// MARK: - Hero header

struct LibraryHeroHeader: View {
    @Environment(AppSession.self) private var appSession
    @Environment(PlaybackViewModel.self) private var playback

    let onRenameTapped: () -> Void
    let onDeleteTapped: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            if case .likedSongs = appSession.selectedLibrary {
                LikedSongsHeartHero(
                    tracks: appSession.likedSongs,
                    isPlayingLikedSong: isPlayingLikedSong
                )
            } else {
                libraryCoverHero
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(libraryHeaderTitle)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    if libraryHeroShowsLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                Text(libraryHeaderInfoLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let desc = libraryHeaderDescription {
                    Text(desc)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }

                libraryActionButtons
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Derived selection

    private var selectedPlaylist: SpotifyPlaylistItem? {
        guard case .playlist(let id) = appSession.selectedLibrary else { return nil }
        return appSession.resolvedPlaylist(id: id)
    }

    private var selectedAlbumSelection: (id: String, nameHint: String?)? {
        guard case .album(let id, let hint) = appSession.selectedLibrary else { return nil }
        return (id, hint)
    }

    private var selectedResolvedAlbum: SpotifyAlbum? {
        guard let sel = selectedAlbumSelection else { return nil }
        return appSession.resolvedAlbum(id: sel.id)
    }

    private var selectedPlaylistIsInUserLibrary: Bool {
        guard case .playlist(let id) = appSession.selectedLibrary else { return false }
        return appSession.playlists.contains { $0.id == id }
    }

    private var selectedPlaylistCanRename: Bool {
        guard let selectedPlaylist else { return false }
        return selectedPlaylist.isOwnedByCurrentUser(appSession.currentSpotifyUserId)
    }

    private var selectedPlaylistDeleteActionTitle: String {
        selectedPlaylistCanRename ? "Delete Playlist" : "Remove from Library"
    }

    // MARK: Text

    private var libraryHeaderTitle: String {
        switch appSession.selectedLibrary {
        case .likedSongs:
            return "Liked Songs"
        case .playlist:
            return selectedPlaylist?.name ?? "Playlist"
        case .album:
            guard let sel = selectedAlbumSelection else { return "Album" }
            return selectedResolvedAlbum?.name ?? sel.nameHint ?? "Album"
        default:
            return ""
        }
    }

    /// Song count from loaded tracks, or playlist total from API metadata while tracks are still loading.
    private var libraryTrackCount: Int {
        let loaded = appSession.tracksForSelectedLibrary
        if case .likedSongs = appSession.selectedLibrary {
            return max(appSession.likedSongsTotalCount, loaded.count)
        }
        if !loaded.isEmpty { return loaded.count }
        if case .playlist = appSession.selectedLibrary {
            return selectedPlaylist?.tracks?.total ?? 0
        }
        if case .album = appSession.selectedLibrary {
            return selectedResolvedAlbum?.total_tracks ?? 0
        }
        return 0
    }

    private var libraryHeroShowsLoading: Bool {
        switch appSession.selectedLibrary {
        case .playlist:
            return appSession.isLoadingPlaylistTracks
        case .likedSongs:
            return appSession.phase == .loadingContent
        case .album:
            return appSession.isLoadingAlbumTracks
        default:
            return false
        }
    }

    private var libraryHeaderInfoLine: String {
        let n = libraryTrackCount
        let loaded = appSession.tracksForSelectedLibrary
        if libraryHeroShowsLoading && n == 0 {
            return "Loading…"
        }
        var parts: [String] = []
        if n == 0 {
            parts.append("0 songs")
        } else {
            parts.append(n == 1 ? "1 song" : "\(n) songs")
        }
        let totalMs = loaded.compactMap(\.duration_ms).reduce(0, +)
        let isFullyLoadedLikedSongs =
            appSession.selectedLibrary != .likedSongs || loaded.count >= max(appSession.likedSongsTotalCount, 0)
        if totalMs > 0, isFullyLoadedLikedSongs {
            parts.append(Self.formatPlaylistDuration(minutesRounded: (totalMs + 30_000) / 60_000))
        }
        return parts.joined(separator: " · ")
    }

    private var libraryHeaderDescription: String? {
        switch appSession.selectedLibrary {
        case .likedSongs:
            return "Your saved tracks"
        case .album:
            guard let album = selectedResolvedAlbum else { return nil }
            var parts: [String] = []
            let artists = album.primaryArtistLine
            if !artists.isEmpty {
                parts.append(artists)
            }
            if let y = album.releaseYearString {
                parts.append(y)
            }
            parts.append("Album")
            return parts.joined(separator: " · ")
        case .playlist:
            guard let raw = selectedPlaylist?.description?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
                return nil
            }
            if raw.contains("<") {
                return raw.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "&nbsp;", with: " ")
                    .replacingOccurrences(of: "&amp;", with: "&")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return raw
        default:
            return nil
        }
    }

    // MARK: Actions

    private var libraryActionButtons: some View {
        VStack(alignment: .leading, spacing: 10) {
            libraryPlayPillButton
            if case .playlist = appSession.selectedLibrary, selectedPlaylist != nil, selectedPlaylistIsInUserLibrary {
                playlistOptionsButton
            }
        }
    }

    /// Current library selection matches active playback (playing **or** paused). Used so the hero pill resumes instead of restarting.
    private var selectedPlaylistMatchesPlayback: Bool {
        guard case .playlist(let id) = appSession.selectedLibrary else { return false }
        guard let np = playback.nowPlaying else { return false }
        return np.contextURI == "spotify:playlist:\(id)"
    }

    private var selectedAlbumMatchesPlayback: Bool {
        guard case .album(let id, _) = appSession.selectedLibrary else { return false }
        guard let np = playback.nowPlaying else { return false }
        return np.contextURI == "spotify:album:\(id)"
    }

    /// Liked Songs has no stable Spotify context URI; treat a liked track as “this page” when it is the current track.
    private var likedSongsSelectionMatchesPlayback: Bool {
        guard case .likedSongs = appSession.selectedLibrary else { return false }
        guard let np = playback.nowPlaying, let uri = np.uri else { return false }
        let trackID = uri.split(separator: ":").last.map(String.init) ?? ""
        return appSession.likedTrackIDs.contains(trackID)
    }

    private var libraryContextMatchesPlayback: Bool {
        selectedPlaylistMatchesPlayback || selectedAlbumMatchesPlayback || likedSongsSelectionMatchesPlayback
    }

    private var libraryHeroShowsPause: Bool {
        libraryContextMatchesPlayback && (playback.nowPlaying?.isPlaying ?? false)
    }

    /// True when a song from the user's liked tracks is currently playing.
    private var isPlayingLikedSong: Bool {
        guard let np = playback.nowPlaying, np.isPlaying else { return false }
        guard let uri = np.uri else { return false }
        let trackID = uri.split(separator: ":").last.map(String.init) ?? ""
        return appSession.likedTrackIDs.contains(trackID)
    }

    private var libraryPlayPillButton: some View {
        Button {
            if libraryContextMatchesPlayback {
                playback.playPause()
            } else {
                playLibrarySelection()
            }
        } label: {
            Label(
                libraryHeroShowsPause ? "Pause" : "Play",
                systemImage: libraryHeroShowsPause ? "pause.fill" : "play.fill"
            )
                .font(.subheadline.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color("AccentColor"))
        .clipShape(Capsule())
        .disabled(!libraryPlayActionEnabled)
        .opacity(libraryPlayActionEnabled ? 1 : 0.45)
    }

    private var playlistOptionsButton: some View {
        Menu {
            if selectedPlaylistCanRename {
                Button("Rename", action: onRenameTapped)
            }
            Button(selectedPlaylistDeleteActionTitle, role: .destructive, action: onDeleteTapped)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32, alignment: .center)
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .disabled(appSession.isMutatingSelectedPlaylist)
        .opacity(appSession.isMutatingSelectedPlaylist ? 0.45 : 1)
        .help("Playlist options")
    }

    private var libraryPlayActionEnabled: Bool {
        guard playback.isWebPlayerReady else { return false }
        switch appSession.selectedLibrary {
        case .likedSongs:
            return !appSession.likedSongs.isEmpty && appSession.phase != .loadingContent
        case .playlist:
            return true
        case .album:
            return true
        default:
            return false
        }
    }

    private func playLibrarySelection() {
        switch appSession.selectedLibrary {
        case .likedSongs:
            playback.playTrackList(trackIDs: appSession.likedSongIDsInOrder)
        case .playlist(let id):
            playback.playContextURI("spotify:playlist:\(id)")
        case .album(let id, _):
            playback.playContextURI("spotify:album:\(id)")
        default:
            break
        }
    }

    private static func formatPlaylistDuration(minutesRounded: Int) -> String {
        guard minutesRounded > 0 else { return "0 min" }
        if minutesRounded >= 60 {
            let h = minutesRounded / 60
            let m = minutesRounded % 60
            return m > 0 ? "\(h) hr \(m) min" : "\(h) hr"
        }
        return "\(minutesRounded) min"
    }

    // MARK: Cover

    private var libraryCoverImageURL: URL? {
        switch appSession.selectedLibrary {
        case .likedSongs:
            return appSession.likedSongs.first?.largestAlbumImageURL
        case .playlist:
            return selectedPlaylist?.coverURL
        case .album:
            return selectedResolvedAlbum?.largestCoverURL
        default:
            return nil
        }
    }

    private var libraryCoverHero: some View {
        let side = LibraryHeroLayout.coverSide
        return Group {
            RemoteArtworkImage(url: libraryCoverImageURL, maxPixelSize: side * 2) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                libraryCoverPlaceholder
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var libraryCoverPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(.quaternary)
            .overlay {
                Image(systemName: libraryCoverPlaceholderSymbol)
                    .foregroundStyle(.secondary)
            }
    }

    private var libraryCoverPlaceholderSymbol: String {
        switch appSession.selectedLibrary {
        case .likedSongs:
            return "heart.fill"
        case .album:
            return "square.stack.fill"
        default:
            return "music.note"
        }
    }
}

// MARK: - Track list sections

struct LikedSongsTrackList: View {
    @Environment(AppSession.self) private var appSession
    @Environment(PlaybackViewModel.self) private var playback

    let onRenameTapped: () -> Void
    let onDeleteTapped: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LibraryHeroHeader(onRenameTapped: onRenameTapped, onDeleteTapped: onDeleteTapped)

            if appSession.tracksForSelectedLibrary.isEmpty, appSession.loadError == nil {
                if appSession.phase != .loadingContent {
                    Text("No tracks in Liked Songs.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if !appSession.tracksForSelectedLibrary.isEmpty {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(appSession.tracksForSelectedLibrary) { track in
                        TrackRow(
                            track: track,
                            onPlay: { playback.playTrack(id: track.id) },
                            onArtistTap: DashboardTrackActions.artistTapAction(appSession: appSession, for: track),
                            onAlbumArtTap: DashboardTrackActions.albumTapAction(appSession: appSession, for: track)
                        )
                        .task(id: track.id) {
                            await appSession.loadMoreLikedSongsIfNeeded(currentTrackID: track.id)
                        }
                        Divider()
                    }

                    if appSession.isLoadingMoreLikedSongs {
                        HStack {
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                            Spacer()
                        }
                        .padding(.vertical, 12)
                    }
                }
            }
        }
    }
}

struct PlaylistTracksSection: View {
    @Environment(AppSession.self) private var appSession
    @Environment(PlaybackViewModel.self) private var playback

    let onRenameTapped: () -> Void
    let onDeleteTapped: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LibraryHeroHeader(onRenameTapped: onRenameTapped, onDeleteTapped: onDeleteTapped)

            if appSession.isPlaylistTrackListForbidden {
                Text(AppSession.playlistTracksUnavailableMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            } else if appSession.tracksForSelectedLibrary.isEmpty, !appSession.isLoadingPlaylistTracks, appSession.loadError == nil {
                Text("No tracks in this playlist.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if !appSession.tracksForSelectedLibrary.isEmpty {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(appSession.tracksForSelectedLibrary) { track in
                        TrackRow(
                            track: track,
                            onPlay: { playback.playTrack(id: track.id) },
                            onArtistTap: DashboardTrackActions.artistTapAction(appSession: appSession, for: track),
                            onAlbumArtTap: DashboardTrackActions.albumTapAction(appSession: appSession, for: track)
                        )
                        Divider()
                    }
                }
            }
        }
    }
}

struct AlbumTracksSection: View {
    @Environment(AppSession.self) private var appSession
    @Environment(PlaybackViewModel.self) private var playback

    let onRenameTapped: () -> Void
    let onDeleteTapped: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LibraryHeroHeader(onRenameTapped: onRenameTapped, onDeleteTapped: onDeleteTapped)

            if appSession.tracksForSelectedLibrary.isEmpty, !appSession.isLoadingAlbumTracks, appSession.loadError == nil {
                Text("No tracks on this album.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if !appSession.tracksForSelectedLibrary.isEmpty {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(appSession.tracksForSelectedLibrary) { track in
                        TrackRow(
                            track: track,
                            onPlay: { playback.playTrack(id: track.id) },
                            onArtistTap: DashboardTrackActions.artistTapAction(appSession: appSession, for: track),
                            onAlbumArtTap: DashboardTrackActions.albumTapAction(appSession: appSession, for: track)
                        )
                        Divider()
                    }
                }
            }
        }
        .alert("Album", isPresented: albumCatalogWarningAlertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(appSession.albumCatalogWarning ?? "")
        }
    }

    private var albumCatalogWarningAlertBinding: Binding<Bool> {
        Binding(
            get: { appSession.albumCatalogWarning != nil },
            set: { newValue in
                if !newValue { appSession.acknowledgeAlbumCatalogWarning() }
            }
        )
    }
}

// MARK: - Shared track tap actions

enum DashboardTrackActions {
    @MainActor
    static func artistTapAction(appSession: AppSession, for track: SpotifyTrack) -> (() -> Void)? {
        guard let aid = track.primaryArtistId else { return nil }
        let hint = track.artists.first?.name
        return {
            Task { await appSession.selectLibrary(.artist(id: aid, nameHint: hint)) }
        }
    }

    @MainActor
    static func albumTapAction(appSession: AppSession, for track: SpotifyTrack) -> (() -> Void)? {
        guard !track.id.isEmpty else { return nil }
        return {
            Task { await appSession.openAlbum(from: track) }
        }
    }
}

// MARK: - Hero gradient

struct LibraryHeroGradient: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.colorScheme) private var colorScheme
    @Binding var heroPalettes: [ArtworkPalette]

    var body: some View {
        ZStack {
            if libraryHasHeroGradient, !heroPalettes.isEmpty {
                Group {
                    heroGradientContent
                        .frame(height: 440)
                        .frame(maxWidth: .infinity)
                        .blur(radius: 32)
                        .opacity(0.95)
                }
                .allowsHitTesting(false)
                .transition(.opacity)
                .ignoresSafeArea(edges: .top)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: heroPalettes.count)
        .task(id: heroGradientTaskKey) {
            await refreshHeroTint()
        }
    }

    var libraryHasHeroGradient: Bool {
        switch appSession.selectedLibrary {
        case .likedSongs, .playlist, .album:
            return true
        default:
            return false
        }
    }

    var heroGradientTaskKey: String {
        guard libraryHasHeroGradient else { return "none" }
        if case .likedSongs = appSession.selectedLibrary {
            let ids = appSession.likedSongs.prefix(5).map(\.id).joined(separator: "|")
            return "likedSongs#\(ids)"
        }
        return libraryCoverImageURL?.absoluteString ?? "placeholder"
    }

    @ViewBuilder
    private var heroGradientContent: some View {
        if case .likedSongs = appSession.selectedLibrary, heroPalettes.count > 1 {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                ZStack {
                    ForEach(Array(heroPalettes.enumerated()), id: \.offset) { index, palette in
                        heroGradientLayer(for: palette)
                            .opacity(crossfadeOpacity(for: index, count: heroPalettes.count, time: t))
                    }
                }
            }
        } else if let palette = heroPalettes.first {
            heroGradientLayer(for: palette)
        }
    }

    private func heroGradientLayer(for palette: ArtworkPalette) -> some View {
        let stop = heroTintStop(for: palette)
        return LinearGradient(
            colors: [
                stop.color.opacity(0.72),
                stop.gradientEnd.opacity(0.32),
                .clear
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func heroTintStop(for palette: ArtworkPalette) -> (color: Color, gradientEnd: Color) {
        if colorScheme == .light {
            return nearestSystemHeroStops(from: palette)
        }
        return (palette.average, palette.averageDark)
    }

    /// Returns the alpha for palette `index` at time `time`, cycling through all palettes
    /// so that exactly two neighbours are visible during any crossfade window.
    private func crossfadeOpacity(for index: Int, count: Int, time: TimeInterval) -> Double {
        guard count > 1 else { return 1 }
        let segment: TimeInterval = 6.0
        let totalCycle = segment * Double(count)
        let cycle = time.truncatingRemainder(dividingBy: totalCycle)
        let position = cycle / segment
        let activeIndex = Int(position.rounded(.down)) % count
        let fraction = position - position.rounded(.down)
        let eased = 0.5 - 0.5 * cos(fraction * .pi)
        let nextIndex = (activeIndex + 1) % count
        if index == activeIndex { return 1 - eased }
        if index == nextIndex { return eased }
        return 0
    }

    private var libraryCoverImageURL: URL? {
        switch appSession.selectedLibrary {
        case .likedSongs:
            return appSession.likedSongs.first?.largestAlbumImageURL
        case .playlist:
            guard case .playlist(let id) = appSession.selectedLibrary else { return nil }
            return appSession.resolvedPlaylist(id: id)?.coverURL
        case .album:
            guard case .album(let id, _) = appSession.selectedLibrary else { return nil }
            return appSession.resolvedAlbum(id: id)?.largestCoverURL
        default:
            return nil
        }
    }

    @MainActor
    func refreshHeroTint() async {
        guard libraryHasHeroGradient else {
            heroPalettes = []
            return
        }

        if case .likedSongs = appSession.selectedLibrary {
            let urls = appSession.likedSongs
                .prefix(5)
                .compactMap(\.largestAlbumImageURL)
            guard !urls.isEmpty else {
                heroPalettes = []
                return
            }

            var palettes: [ArtworkPalette] = []
            for url in urls {
                do {
                    let image = try await ArtworkPipeline.shared.image(for: url, maxPixelSize: 96)
                    if let palette = ArtworkColorSampler.palette(from: image) {
                        palettes.append(palette)
                    }
                } catch {
                    continue
                }
            }
            heroPalettes = palettes
            return
        }

        guard let url = libraryCoverImageURL else {
            heroPalettes = []
            return
        }
        do {
            let image = try await ArtworkPipeline.shared.image(for: url, maxPixelSize: 96)
            if let palette = ArtworkColorSampler.palette(from: image) {
                heroPalettes = [palette]
            } else {
                heroPalettes = []
            }
        } catch {
            heroPalettes = []
        }
    }
}

// MARK: - Liked Songs heart hero

/// Hero visual for the Liked Songs page: a small SF Symbol heart surrounded by
/// seven liked-song covers orbiting on a tilted ellipse. Pressing and holding
/// the heart "gravitates" the covers inward; releasing springs them back out.
/// The heart slowly breathes (scale in/out) while a liked song is playing.
private struct LikedSongsHeartHero: View {
    let tracks: [SpotifyTrack]
    let isPlayingLikedSong: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isPulled: Bool = false
    @State private var pressFeedback: Int = 0

    private static let heroSide: CGFloat = 220
    private static let heartSize: CGFloat = 44
    private static let baseRadius: CGFloat = 88
    private static let pulledScale: CGFloat = 0.74
    /// Varied cover sizes so the orbit feels more characterful than a wheel of clones.
    /// Cycled by index so any count of tracks gets a distinct rhythm.
    private static let coverSides: [CGFloat] = [56, 38, 50, 44, 58, 40, 48]

    private var orbitingTracks: [SpotifyTrack] {
        Array(tracks.prefix(7))
    }

    private var angularSpeed: Double { reduceMotion ? 0 : 0.22 }

    var body: some View {
        ZStack {
            if orbitingTracks.isEmpty {
                if isPlayingLikedSong && !reduceMotion {
                    TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
                        heartView(at: context.date)
                    }
                } else {
                    heartView(at: nil)
                }
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    let rotation = t * angularSpeed
                    let count = orbitingTracks.count
                    let radius = Self.baseRadius * (isPulled ? Self.pulledScale : 1.0)

                    ZStack {
                        ForEach(Array(orbitingTracks.enumerated()), id: \.element.id) { index, track in
                            let angle = (Double(index) / Double(count)) * 2 * .pi - .pi / 2 + rotation
                            let s = sin(angle)
                            let x = CGFloat(cos(angle)) * radius
                            let y = CGFloat(s) * radius
                            let side = Self.coverSides[index % Self.coverSides.count]

                            OrbitingCover(track: track, side: side)
                                .offset(x: x, y: y)
                                .zIndex(s)
                        }

                        heartView(at: context.date)
                            .zIndex(0)
                    }
                }
            }
        }
        .frame(width: Self.heroSide, height: Self.heroSide)
        .contentShape(Rectangle())
        .gesture(gravitateGesture)
        .animation(.spring(duration: 0.55, bounce: 0.28), value: isPulled)
        .animation(.spring(duration: 0.9, bounce: 0.3), value: orbitingTracks.map(\.id))
        .sensoryFeedback(.impact(weight: .light), trigger: pressFeedback)
    }

    /// Press-and-hold: covers gravitate inward while finger is down, spring back on release.
    private var gravitateGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if !isPulled {
                    isPulled = true
                    pressFeedback &+= 1
                }
            }
            .onEnded { _ in
                isPulled = false
            }
    }

    private func heartView(at animationDate: Date?) -> some View {
        let beatScale: CGFloat = {
            guard isPlayingLikedSong && !reduceMotion, let animationDate else { return 1.0 }
            return Self.breathingScale(at: animationDate)
        }()
        return heartImage(beatScale: beatScale)
    }

    /// Size-only slow breathe while playing (sine in/out, no opacity).
    private static func breathingScale(at date: Date) -> CGFloat {
        let period: TimeInterval = 2.75
        let phase = 2 * Double.pi * date.timeIntervalSinceReferenceDate / period
        return CGFloat(1.0 + 0.04 * sin(phase))
    }

    private func heartImage(beatScale: CGFloat) -> some View {
        let pullScale: CGFloat = isPulled ? 0.98 : 1.0

        return Image(systemName: "heart.fill")
            .resizable()
            .scaledToFit()
            .frame(width: Self.heartSize, height: Self.heartSize)
            .foregroundStyle(Color("AccentColor"))
            .shadow(color: .black.opacity(0.3), radius: 7, y: 3)
            .scaleEffect(beatScale * pullScale)
    }
}

private struct OrbitingCover: View {
    let track: SpotifyTrack
    let side: CGFloat

    var body: some View {
        RemoteArtworkImage(url: track.largestAlbumImageURL, maxPixelSize: side * 2) { image in
            image
                .resizable()
                .aspectRatio(1, contentMode: .fill)
        } placeholder: {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.quaternary)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 5, y: 2)
    }
}
