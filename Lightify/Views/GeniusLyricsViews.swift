//
//  GeniusLyricsViews.swift
//  Lightify
//

import SwiftUI

// MARK: - Formatting (bracket labels bold, hide round parens)

enum LyricsDisplayFormat {
    /// Square brackets: section tags (`[Verse 1]`, `[Chorus]`, …) keep visible `[]` with semibold inner; other `[…]` notes stay semibold inner only. Plain segments: strip `(...)`.
    static func attributedLine(_ line: String) -> AttributedString {
        var result = AttributedString()
        var rest = line[...]

        while !rest.isEmpty {
            guard let openIdx = rest.firstIndex(of: "[") else {
                result.append(AttributedString(stripRoundParentheticals(String(rest))))
                break
            }

            if openIdx > rest.startIndex {
                let plain = rest[..<openIdx]
                result.append(AttributedString(stripRoundParentheticals(String(plain))))
            }

            let afterOpen = rest.index(after: openIdx)
            guard let closeIdx = rest[afterOpen...].firstIndex(of: "]") else {
                result.append(AttributedString(stripRoundParentheticals(String(rest))))
                break
            }

            let inner = rest[afterOpen..<closeIdx]
            let innerStr = String(inner)
            let showBrackets = isGeniusSectionBracketInner(innerStr)
            if showBrackets {
                var openBracket = AttributedString("[")
                openBracket.font = .body.weight(.semibold)
                openBracket.foregroundColor = .primary
                result.append(openBracket)
            }
            var boldPart = AttributedString(innerStr)
            boldPart.font = .body.weight(.semibold)
            boldPart.foregroundColor = .primary
            result.append(boldPart)
            if showBrackets {
                var closeBracket = AttributedString("]")
                closeBracket.font = .body.weight(.semibold)
                closeBracket.foregroundColor = .primary
                result.append(closeBracket)
            }

            rest = rest[rest.index(after: closeIdx)...]
        }

        return result
    }

    /// Plain lyric segments in the line use secondary color; bracket labels stay primary/semibold.
    static func attributedLineSecondaryPlain(_ line: String) -> AttributedString {
        var result = AttributedString()
        var rest = line[...]

        while !rest.isEmpty {
            guard let openIdx = rest.firstIndex(of: "[") else {
                var plain = AttributedString(stripRoundParentheticals(String(rest)))
                plain.foregroundColor = .secondary
                result.append(plain)
                break
            }

            if openIdx > rest.startIndex {
                let plain = rest[..<openIdx]
                var chunk = AttributedString(stripRoundParentheticals(String(plain)))
                chunk.foregroundColor = .secondary
                result.append(chunk)
            }

            let afterOpen = rest.index(after: openIdx)
            guard let closeIdx = rest[afterOpen...].firstIndex(of: "]") else {
                var tail = AttributedString(stripRoundParentheticals(String(rest)))
                tail.foregroundColor = .secondary
                result.append(tail)
                break
            }

            let inner = rest[afterOpen..<closeIdx]
            let innerStr = String(inner)
            let showBrackets = isGeniusSectionBracketInner(innerStr)
            if showBrackets {
                var openBracket = AttributedString("[")
                openBracket.font = .body.weight(.semibold)
                openBracket.foregroundColor = .primary
                result.append(openBracket)
            }
            var boldPart = AttributedString(innerStr)
            boldPart.font = .body.weight(.semibold)
            boldPart.foregroundColor = .primary
            result.append(boldPart)
            if showBrackets {
                var closeBracket = AttributedString("]")
                closeBracket.font = .body.weight(.semibold)
                closeBracket.foregroundColor = .primary
                result.append(closeBracket)
            }

            rest = rest[rest.index(after: closeIdx)...]
        }

        return result
    }

    /// Matches structural labels so we keep `[` `]` visible (they are not “parsed away”).
    private static func isGeniusSectionBracketInner(_ inner: String) -> Bool {
        let t = inner.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        guard let re = try? NSRegularExpression(
            pattern: #"^(?i)(verse|chorus|refrain|hook|bridge|pre-chorus|post-chorus|outro|intro|interlude|break|instrumental|part|skit)\b"#,
            options: []
        ) else { return false }
        let range = NSRange(t.startIndex..<t.endIndex, in: t)
        return re.firstMatch(in: t, options: [], range: range) != nil
    }

    static func stripRoundParentheticals(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if isStandaloneSectionLabelInParentheses(trimmed) {
            return trimmed
                .dropFirst()
                .dropLast()
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let re = try? NSRegularExpression(pattern: #"\([^)]*\)"#, options: []) else {
            return s
        }
        let full = NSRange(s.startIndex..<s.endIndex, in: s)
        var t = re.stringByReplacingMatches(in: s, options: [], range: full, withTemplate: "")
        t = t.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        return t
    }

    private static func isStandaloneSectionLabelInParentheses(_ s: String) -> Bool {
        let pattern = #"^\((?i)(verse|chorus|refrain|hook|bridge|pre-chorus|post-chorus|outro|intro|interlude|break|instrumental|part)\b[^)]*\)$"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: []) else { return false }
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        return re.firstMatch(in: s, options: [], range: range) != nil
    }
}

private struct LyricsViewportMidYKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct LyricLineMetric: Equatable {
    let index: Int
    let midY: CGFloat
}

private struct LyricsLineMetricsKey: PreferenceKey {
    static var defaultValue: [LyricLineMetric] = []

    static func reduce(value: inout [LyricLineMetric], nextValue: () -> [LyricLineMetric]) {
        value.append(contentsOf: nextValue())
    }
}

// MARK: - LRCLIB attribution

private struct LRCLIBAttributionChip: View {
    var body: some View {
        Text("Lyrics from LRCLIB")
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
            .allowsHitTesting(false)
    }
}

// MARK: - Line-by-line (plain)

/// One row per lyric line with center-weighted emphasis. Scroll is manual when timestamps are unavailable.
struct PlainLyricsLineByLineView: View {
    let lyrics: String

    @State private var viewportMidY: CGFloat = 0
    @State private var metrics: [LyricLineMetric] = []

    private var lines: [String] {
        lyrics
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0) }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            lyricLine(line, index: index)
                        }
                    }
                    .padding(.horizontal, 36)
                    .padding(.vertical, max(proxy.size.height * 0.3, 120))
                }
                .coordinateSpace(name: "LyricsScrollSpace")
                .background {
                    GeometryReader { scrollProxy in
                        Color.clear
                            .preference(
                                key: LyricsViewportMidYKey.self,
                                value: scrollProxy.frame(in: .named("LyricsScrollSpace")).midY
                            )
                    }
                }
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white.opacity(0.72), location: 0.12),
                            .init(color: .white, location: 0.34),
                            .init(color: .white, location: 0.66),
                            .init(color: .white.opacity(0.72), location: 0.88),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .onPreferenceChange(LyricsViewportMidYKey.self) { viewportMidY = $0 }
                .onPreferenceChange(LyricsLineMetricsKey.self) { metrics = $0 }
                .background(Color.clear)

                LRCLIBAttributionChip()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clear)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }

    private func lyricLine(_ line: String, index: Int) -> some View {
        let emphasis = emphasisForLine(at: index)
        return Text(LyricsDisplayFormat.attributedLine(line))
            .font(.system(size: 19 + (emphasis * 9), weight: emphasis > 0.78 ? .bold : .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.18 + (emphasis * 0.82)))
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .scaleEffect(0.97 + (emphasis * 0.05), anchor: .leading)
            .blur(radius: emphasis < 0.18 ? 0.6 : 0)
            .animation(.smooth(duration: 0.16), value: emphasis)
            .background {
                GeometryReader { lineProxy in
                    Color.clear.preference(
                        key: LyricsLineMetricsKey.self,
                        value: [
                            LyricLineMetric(
                                index: index,
                                midY: lineProxy.frame(in: .named("LyricsScrollSpace")).midY
                            )
                        ]
                    )
                }
            }
    }

    private func emphasisForLine(at index: Int) -> CGFloat {
        guard let lineMidY = metrics.last(where: { $0.index == index })?.midY, viewportMidY > 0 else {
            return index == 0 ? 0.9 : 0.42
        }

        let distance = abs(lineMidY - viewportMidY)
        let fadeDistance: CGFloat = 240
        let normalized = max(0, min(1, 1 - (distance / fadeDistance)))
        return pow(normalized, 1.35)
    }
}

// MARK: - Time-synced (LRCLIB LRC)

struct SyncedLyricsScrollView: View {
    let lines: [SyncedLyricLine]
    let positionMs: Int
    let isPlaying: Bool

    private static let scrollSpring = Animation.spring(duration: 0.52, bounce: 0.22)

    private var activeIndex: Int {
        Self.activeLineIndex(lines: lines, positionMs: positionMs)
    }

    private static func activeLineIndex(lines: [SyncedLyricLine], positionMs: Int) -> Int {
        guard !lines.isEmpty else { return 0 }
        var low = 0
        var high = lines.count - 1
        var best = 0
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].startMs <= positionMs {
                best = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return best
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                ScrollViewReader { scrollProxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            ForEach(Array(lines.enumerated()), id: \.element.id) { idx, line in
                                SyncedLyricLineView(
                                    line: line,
                                    rankDistance: abs(idx - activeIndex),
                                    isCurrent: idx == activeIndex,
                                    isPlaying: isPlaying
                                )
                                .id(line.id)
                            }
                        }
                        .padding(.horizontal, 32)
                        .padding(.vertical, max(proxy.size.height * 0.28, 100))
                    }
                    .coordinateSpace(name: "SyncedLyricsSpace")
                    .mask {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .white.opacity(0.7), location: 0.1),
                                .init(color: .white, location: 0.32),
                                .init(color: .white, location: 0.68),
                                .init(color: .white.opacity(0.7), location: 0.9),
                                .init(color: .clear, location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .onChange(of: activeIndex) { _, newIdx in
                        guard lines.indices.contains(newIdx) else { return }
                        withAnimation(Self.scrollSpring) {
                            scrollProxy.scrollTo(lines[newIdx].id, anchor: UnitPoint(x: 0.5, y: 0.34))
                        }
                    }
                    .onAppear {
                        let idx = activeIndex
                        guard lines.indices.contains(idx) else { return }
                        DispatchQueue.main.async {
                            scrollProxy.scrollTo(lines[idx].id, anchor: UnitPoint(x: 0.5, y: 0.34))
                        }
                    }
                }

                LRCLIBAttributionChip()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SyncedLyricLineView: View {
    let line: SyncedLyricLine
    let rankDistance: Int
    let isCurrent: Bool
    let isPlaying: Bool

    private var depthFade: CGFloat {
        let d = CGFloat(min(rankDistance, 12))
        return pow(max(0, 1 - d * 0.085), 1.15)
    }

    private var attributed: AttributedString {
        LyricsDisplayFormat.attributedLine(line.text)
    }

    var body: some View {
        let fontSize: CGFloat = isCurrent ? 22 : (14.5 + depthFade * 2.8)
        let opacity: CGFloat = isCurrent ? 1 : (0.26 + 0.48 * depthFade)
        let scale: CGFloat = isCurrent ? 1.045 : (0.965 + 0.035 * depthFade)

        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Capsule()
                .fill(Color.white.opacity(isCurrent ? 0.95 : (0.12 + 0.14 * depthFade)))
                .frame(width: isCurrent ? 5 : 2.5, height: isCurrent ? 28 : max(9, 11 * depthFade))
                .shadow(color: .white.opacity(isCurrent ? (isPlaying ? 0.5 : 0.28) : 0), radius: isCurrent ? 16 : 0, y: 0)
                .animation(.spring(duration: 0.38, bounce: 0.2), value: isCurrent)

            ZStack(alignment: .leading) {
                if isCurrent {
                    Text(attributed)
                        .font(.system(size: fontSize, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.35))
                        .blur(radius: 16)
                        .offset(x: 0, y: 1)
                }

                Text(attributed)
                    .font(.system(size: fontSize, weight: isCurrent ? .bold : .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(Double(opacity)))
                    .overlay {
                        if isCurrent {
                            TimelineView(.animation(minimumInterval: .milliseconds(isPlaying ? 22 : 500), paused: !isPlaying)) { ctx in
                                let t = ctx.date.timeIntervalSinceReferenceDate
                                let sweep = (sin(t * 2.05) + 1) * 0.5
                                LinearGradient(
                                    stops: [
                                        .init(color: .clear, location: 0),
                                        .init(color: .white.opacity(0.18 + sweep * 0.14), location: 0.35 + sweep * 0.12),
                                        .init(color: .clear, location: 1)
                                    ],
                                    startPoint: UnitPoint(x: -0.45 + sweep * 0.35, y: 0.5),
                                    endPoint: UnitPoint(x: 0.55 + sweep * 0.45, y: 0.5)
                                )
                                .blendMode(.plusLighter)
                                .mask(
                                    Text(attributed)
                                        .font(.system(size: fontSize, weight: .bold, design: .rounded))
                                )
                            }
                        }
                    }
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .scaleEffect(x: scale, y: scale, anchor: .leading)
        }
        .animation(.spring(duration: 0.4, bounce: 0.16), value: isCurrent)
        .animation(.spring(duration: 0.36, bounce: 0.14), value: rankDistance)
    }
}

// MARK: - Fetch + load (mini player)

struct MiniPlayerLyricsPanel: View {
    let trackName: String
    let artistName: String
    let albumName: String?
    let durationMs: Int
    let positionMs: Int
    let isPlaying: Bool

    @State private var loadState: LoadState = .idle

    private enum LoadState: Equatable {
        case idle
        case loading
        case loaded(LRCLIBFetchedLyrics)
        case failed(String)
    }

    var body: some View {
        Group {
            switch loadState {
            case .idle, .loading:
                ProgressView("Loading lyrics…")
                    .tint(.white.opacity(0.9))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let payload):
                lyricsBody(for: payload)
            case .failed(let message):
                Text(message)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(28)
            }
        }
        .task(id: "\(trackName)|\(artistName)|\(albumName ?? "")|\(durationMs)") {
            await fetchLyrics()
        }
    }

    @ViewBuilder
    private func lyricsBody(for payload: LRCLIBFetchedLyrics) -> some View {
        let hasSynced = (payload.syncedLines?.isEmpty == false)
        let hasPlain = !payload.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if payload.instrumental && !hasSynced && !hasPlain {
            Text("Instrumental")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    LRCLIBAttributionChip()
                }
        } else if hasSynced, let synced = payload.syncedLines {
            SyncedLyricsScrollView(lines: synced, positionMs: positionMs, isPlaying: isPlaying)
        } else if hasPlain {
            PlainLyricsLineByLineView(lyrics: payload.plainText)
        } else {
            Text("No lyric lines for this track.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.72))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func fetchLyrics() async {
        loadState = .loading
        do {
            let payload = try await LRCLIBLyricsService().fetchLyrics(
                trackName: trackName,
                artistName: artistName,
                albumName: albumName,
                durationMs: durationMs
            )
            loadState = .loaded(payload)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            loadState = .failed(message)
        }
    }
}
