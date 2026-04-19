//
//  GeniusLyricsViews.swift
//  Lightify
//

import SwiftUI

// MARK: - Formatting (bracket labels bold, hide round parens)

enum LyricsDisplayFormat {
    /// Square brackets: Genius section tags (`[Verse 1]`, `[Chorus]`, …) keep visible `[]` with semibold inner; other `[…]` notes stay semibold inner only. Plain segments: strip `(...)`.
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

    /// Matches Genius-style structural labels so we keep `[` `]` visible (they are not “parsed away”).
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

// MARK: - Line-by-line (now playing expanded; no playback sync)

/// One row per lyric line with center-weighted emphasis to mimic the large, focused lyric wall.
struct GeniusLyricsLineByLineView: View {
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
                LazyVStack(alignment: .leading, spacing: 22) {
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

// MARK: - Fetch + load (mini player)

struct MiniPlayerLyricsPanel: View {
    let trackName: String
    let artistName: String

    @State private var loadState: LoadState = .idle

    private enum LoadState: Equatable {
        case idle
        case loading
        case loaded(String)
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
            case .loaded(let text):
                GeniusLyricsLineByLineView(lyrics: text)
            case .failed(let message):
                Text(message)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(28)
            }
        }
        .task(id: "\(trackName)|\(artistName)") {
            await fetchLyrics()
        }
    }

    private func fetchLyrics() async {
        loadState = .loading
        do {
            let text = try await GeniusLyricsService().fetchLyrics(title: trackName, artist: artistName)
            loadState = .loaded(text)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            loadState = .failed(message)
        }
    }
}
