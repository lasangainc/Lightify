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

// MARK: - Minimal placeholders

private struct NoLyricsPlaceholder: View {
    var body: some View {
        Text("...")
            .font(.system(size: 32, weight: .regular, design: .default))
            .foregroundStyle(.white.opacity(0.45))
            .tracking(2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 26) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        lyricLine(line, index: index)
                    }
                }
                .padding(.horizontal, 28)
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
                        .init(color: .white.opacity(0.85), location: 0.08),
                        .init(color: .white, location: 0.22),
                        .init(color: .white, location: 0.78),
                        .init(color: .white.opacity(0.85), location: 0.92),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .onPreferenceChange(LyricsViewportMidYKey.self) { viewportMidY = $0 }
            .onPreferenceChange(LyricsLineMetricsKey.self) { metrics = $0 }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func lyricLine(_ line: String, index: Int) -> some View {
        let emphasis = emphasisForLine(at: index)
        let fontSize: CGFloat = 17 + (emphasis * 5)
        let blurRadius: CGFloat = emphasis > 0.72 ? 0 : min(14, 3.5 + (1 - emphasis) * 16)
        let opacity: CGFloat = 0.22 + (emphasis * 0.78)
        return Text(LyricsDisplayFormat.attributedLine(line))
            .font(.system(size: fontSize, weight: emphasis > 0.75 ? .semibold : .regular, design: .default))
            .foregroundStyle(.white.opacity(Double(opacity)))
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .blur(radius: blurRadius)
            .animation(.smooth(duration: 0.18), value: emphasis)
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
            ScrollViewReader { scrollProxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 26) {
                        ForEach(Array(lines.enumerated()), id: \.element.id) { idx, line in
                            SyncedLyricLineView(
                                line: line,
                                rankDistance: abs(idx - activeIndex),
                                isCurrent: idx == activeIndex
                            )
                            .id(line.id)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, max(proxy.size.height * 0.28, 100))
                }
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white.opacity(0.88), location: 0.08),
                            .init(color: .white, location: 0.2),
                            .init(color: .white, location: 0.8),
                            .init(color: .white.opacity(0.88), location: 0.92),
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SyncedLyricLineView: View {
    let line: SyncedLyricLine
    let rankDistance: Int
    let isCurrent: Bool

    private var displayText: String {
        LyricsDisplayFormat.stripRoundParentheticals(line.text)
    }

    /// Softer lines further from the active lyric (reference-style depth).
    private var inactiveBlur: CGFloat {
        guard !isCurrent else { return 0 }
        let d = CGFloat(min(rankDistance, 10))
        return min(11, 4 + d * 0.85)
    }

    private var inactiveOpacity: CGFloat {
        guard !isCurrent else { return 1 }
        let d = CGFloat(min(rankDistance, 8))
        return max(0.28, 0.72 - d * 0.055)
    }

    var body: some View {
        let fontSize: CGFloat = isCurrent ? 23 : 17
        let weight: Font.Weight = isCurrent ? .semibold : .regular

        Text(displayText)
            .font(.system(size: fontSize, weight: weight, design: .default))
            .foregroundStyle(Color.white.opacity(Double(isCurrent ? 1 : inactiveOpacity)))
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .blur(radius: inactiveBlur)
            .animation(.smooth(duration: 0.2), value: isCurrent)
            .animation(.smooth(duration: 0.2), value: rankDistance)
    }
}

// MARK: - Fetch + load (mini player)

struct MiniPlayerLyricsPanel: View {
    let trackName: String
    let artistName: String
    let albumName: String?
    let durationMs: Int
    let positionMs: Int

    @State private var loadState: LoadState = .idle

    private enum LoadState: Equatable {
        case idle
        case loading
        case loaded(LRCLIBFetchedLyrics)
        case failed
    }

    var body: some View {
        Group {
            switch loadState {
            case .idle, .loading:
                ProgressView()
                    .controlSize(.regular)
                    .tint(.white.opacity(0.35))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let payload):
                lyricsBody(for: payload)
            case .failed:
                NoLyricsPlaceholder()
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
            NoLyricsPlaceholder()
        } else if hasSynced, let synced = payload.syncedLines {
            SyncedLyricsScrollView(lines: synced, positionMs: positionMs)
        } else if hasPlain {
            PlainLyricsLineByLineView(lyrics: payload.plainText)
        } else {
            NoLyricsPlaceholder()
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
            loadState = .failed
        }
    }
}
