//
//  GeniusLyricsService.swift
//  Lightify
//
//  Fetches genius.com lyric pages: try canonical URL, then `/api/search/multi` (JSON), then parse song HTML.
//  Primary URL pattern: https://genius.com/{artistSlug}-{titleSlug}-lyrics
//  Lyrics live in <main>, in divs with data-lyrics-container="true".
//

import Foundation

enum GeniusLyricsError: Error, LocalizedError, Sendable {
    case noSearchResults
    case emptyLyrics
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .noSearchResults:
            return "No Genius match for this track."
        case .emptyLyrics:
            return "Could not read lyrics from the Genius page."
        case .invalidResponse:
            return "Unexpected response from Genius."
        case .httpStatus(let code):
            return "Request failed (HTTP \(code))."
        }
    }
}

/// Load Genius lyric pages (direct URL or search API), parse `data-lyrics-container` inside `<main>`.
struct GeniusLyricsService: Sendable {
    private let session: URLSession

    nonisolated init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchLyrics(title: String, artist: String) async throws -> String {
        let artistT = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleT = Self.normalizedTrackTitleForGenius(title.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !artistT.isEmpty, !titleT.isEmpty else {
            throw GeniusLyricsError.noSearchResults
        }

        /// Primary: `https://genius.com/{artist-slug}-{title-slug}-lyrics`
        if let directURL = Self.geniusLyricsPageURL(artist: artistT, title: titleT) {
            if let html = try await fetchHTML(url: directURL, requireHTTP200: false),
               let lyrics = Self.extractLyricsFromSongPageHTML(html),
               !lyrics.isEmpty {
                return lyrics
            }
        }

        let query = [artistT, titleT].joined(separator: " ")
        guard let songURL = try await songLyricsURLFromSearchMulti(
            query: query,
            artist: artistT,
            title: titleT
        ) else {
            throw GeniusLyricsError.noSearchResults
        }

        guard let pageHTML = try await fetchHTML(url: songURL, requireHTTP200: true) else {
            throw GeniusLyricsError.httpStatus(0)
        }

        guard let lyrics = Self.extractLyricsFromSongPageHTML(pageHTML), !lyrics.isEmpty else {
            throw GeniusLyricsError.emptyLyrics
        }
        return lyrics
    }

    /// When `requireHTTP200` is false, returns `nil` for non-200 (e.g. wrong guessed slug).
    private func fetchHTML(url: URL, requireHTTP200: Bool) async throws -> String? {
        var request = URLRequest(url: url)
        request.setValue(Self.browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status != 200 {
            if requireHTTP200 {
                throw GeniusLyricsError.httpStatus(status)
            }
            return nil
        }
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw GeniusLyricsError.invalidResponse
        }
        return html
    }

    /// Genius search HTML embeds unrelated `hot_songs_preview` links before real results; the public multi search API returns ordered hits instead.
    private func songLyricsURLFromSearchMulti(query: String, artist: String, title: String) async throws -> URL? {
        var searchComponents = URLComponents(string: "https://genius.com/api/search/multi")!
        searchComponents.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let searchURL = searchComponents.url else { return nil }

        var request = URLRequest(url: searchURL)
        request.setValue(Self.browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { return nil }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseObj = root["response"] as? [String: Any],
              let sections = responseObj["sections"] as? [[String: Any]]
        else { return nil }

        var bestURL: URL?
        var bestScore = -1

        for section in sections {
            guard let hits = section["hits"] as? [[String: Any]] else { continue }
            for hit in hits {
                guard let hitType = hit["type"] as? String, hitType == "song",
                      let result = hit["result"] as? [String: Any],
                      let resultType = result["_type"] as? String, resultType == "song",
                      let urlString = result["url"] as? String,
                      let url = URL(string: urlString),
                      let core = Self.lyricsSlugCore(fromGeniusPath: url.path)
                else { continue }

                let score = Self.geniusSearchHitScore(
                    lyricsSlugCore: core,
                    artist: artist,
                    title: title,
                    fullTitle: result["full_title"] as? String
                )
                if score > bestScore {
                    bestScore = score
                    bestURL = url
                }
            }
        }

        /// Reject weak substring matches (they were a common source of wrong songs when HTML search was used).
        return bestScore >= 250 ? bestURL : nil
    }

    private static let browserUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    // MARK: - Direct URL (genius.com/Artist-song-lyrics)

    /// Strips common featured-artist suffixes so slugs match Genius URLs better.
    private static func normalizedTrackTitleForGenius(_ title: String) -> String {
        var t = title
        let cutMarkers = [" (feat.", " (ft.", " (with ", " [feat.", " feat."]
        for m in cutMarkers {
            if let r = t.range(of: m, options: .caseInsensitive) {
                t = String(t[..<r.lowerBound])
            }
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func geniusSlugSegment(_ raw: String) -> String {
        let folded = raw.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
        var result: [Character] = []
        var lastWasHyphen = false
        for c in folded.lowercased() {
            if c.isLetter || c.isNumber {
                result.append(c)
                lastWasHyphen = false
            } else if c == "'" || c == "\u{2019}" || c == "\"" || c == "\u{201d}" || c == "\u{201c}" {
                continue
            } else {
                if !result.isEmpty, !lastWasHyphen {
                    result.append("-")
                    lastWasHyphen = true
                }
            }
        }
        while result.last == "-" { result.removeLast() }
        while result.first == "-" { result.removeFirst() }
        return String(result)
    }

    private static func geniusLyricsPageURL(artist: String, title: String) -> URL? {
        let a = geniusSlugSegment(artist)
        let t = geniusSlugSegment(title)
        guard !a.isEmpty, !t.isEmpty else { return nil }
        return URL(string: "https://genius.com/\(a)-\(t)-lyrics")
    }

    /// Primary song pages use a single path segment ending in `-lyrics` (not `/albums/...` or `...-annotated`).
    private static func lyricsSlugCore(fromGeniusPath path: String) -> String? {
        let segments = path.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        guard segments.count == 1 else { return nil }
        let leaf = segments[0].lowercased()
        guard leaf.hasSuffix("-lyrics") else { return nil }
        return String(leaf.dropLast("-lyrics".count))
    }

    private static func geniusSearchHitScore(
        lyricsSlugCore core: String,
        artist: String,
        title: String,
        fullTitle: String?
    ) -> Int {
        let a = geniusSlugSegment(artist)
        let t = geniusSlugSegment(title)
        guard !a.isEmpty, !t.isEmpty else { return -1 }

        let expected = a + "-" + t
        let score: Int
        if core == expected {
            score = 1000
        } else if core.hasPrefix(expected + "-") {
            score = 850
        } else if core.hasPrefix(a + "-"), core.contains(t) {
            score = 700
        } else if core.split(separator: "-").contains(where: { $0 == a }), core.contains(t) {
            score = 550
        } else if core.contains(a), core.contains(t) {
            score = 400
        } else if core.hasPrefix(a + "-") {
            score = 250
        } else if core.contains(a) || core.contains(t) {
            score = 120
        } else {
            return -1
        }

        var adjusted = score
        let ft = fullTitle?.lowercased() ?? ""
        let penaltyTerms = ["translation", "перевод", "türkçe", "русский", "annotated"]
        if penaltyTerms.contains(where: { ft.contains($0) }) {
            adjusted -= 200
        }
        if ft.contains("live"), !title.lowercased().contains("live") {
            adjusted -= 80
        }
        return adjusted
    }

    // MARK: - Lyrics DOM (inside `<main>` only)

    /// Parses only `<main>…</main>` so About, nav, and scripts are excluded.
    private static func htmlMainFragment(_ html: String) -> String {
        guard let mainOpen = html.range(of: "<main", options: .caseInsensitive) else {
            return html
        }
        let fromMain = html[mainOpen.lowerBound...]
        guard let close = fromMain.range(of: "</main>", options: .caseInsensitive) else {
            return String(fromMain)
        }
        return String(fromMain[..<close.upperBound])
    }

    /// Concatenates non-empty `data-lyrics-container` blocks in document order.
    private static func extractLyricsFromSongPageHTML(_ fullHTML: String) -> String? {
        let scoped = htmlMainFragment(fullHTML)
        var extracted = extractLyricsFromDataContainers(scoped)
        extracted = normalizeLyricWhitespace(extracted)
        extracted = trimLeadingGeniusChrome(extracted)
        let trimmed = extracted.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Strips contributor counts, translation lists, and song bio before the first section label.
    /// Accepts the common Genius form (`[Verse 1: …]`) plus looser bare/parenthetical variants.
    private static func trimLeadingGeniusChrome(_ s: String) -> String {
        let lines = s.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        for (i, line) in lines.enumerated() {
            let t = trimLineForSectionParsing(line)
            if t.isEmpty { continue }

            if isLikelySectionHeader(t) {
                return lines[i...].joined(separator: "\n")
            }

            // Section tag sometimes shares a line with song description HTML; keep from `[Verse …]` onward.
            if let slice = sliceFromFirstEmbeddedSectionTag(t), isLikelySectionHeader(slice) {
                var tail = Array(lines[i...])
                tail[0] = slice
                return tail.joined(separator: "\n")
            }
        }
        return s
    }

    /// Trims horizontal/vertical whitespace plus invisible format characters Genius sometimes embeds at line edges (referent HTML).
    private static func trimLineForSectionParsing(_ line: String) -> String {
        var t = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let edgeBidiAndFormat: Set<UInt32> = {
            var s = Set<UInt32>([0x200B, 0x200C, 0x200E, 0x200F, 0xFEFF])
            for v in 0x202A...0x202E { s.insert(UInt32(v)) }
            for v in 0x2060...0x2064 { s.insert(UInt32(v)) }
            return s
        }()
        while let first = t.unicodeScalars.first?.value, edgeBidiAndFormat.contains(first) {
            t.removeFirst()
        }
        while let last = t.unicodeScalars.last?.value, edgeBidiAndFormat.contains(last) {
            t.removeLast()
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// If the line contains a section label after song description text on the same line, returns from `[Verse …]` / `[Chorus]` / … onward.
    private static func sliceFromFirstEmbeddedSectionTag(_ line: String) -> String? {
        guard let re = try? NSRegularExpression(
            pattern: #"\[(Verse\s*\d+|Chorus|Hook|Intro|Outro|Bridge|Refrain|Interlude|Pre-Chorus|Post-Chorus|Instrumental)"#,
            options: [.caseInsensitive]
        ) else { return nil }
        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let m = re.firstMatch(in: line, options: [], range: full),
              let r = Range(m.range, in: line)
        else { return nil }
        return String(line[r.lowerBound...])
    }

    /// Collapses odd-width spaces Genius uses inside annotated lines.
    private static func normalizeLyricWhitespace(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{2005}", with: " ") // four-per-em
            .replacingOccurrences(of: "\u{2009}", with: " ") // thin
            .replacingOccurrences(of: "\u{200b}", with: "") // ZWSP (Genius inserts these in markup)
            .replacingOccurrences(of: "\u{feff}", with: "") // BOM
    }

    private static func extractLyricsFromDataContainers(_ html: String) -> String {
        var pieces: [String] = []
        var searchStart = html.startIndex

        while searchStart < html.endIndex {
            guard let markerRange = html.range(of: "data-lyrics-container", range: searchStart..<html.endIndex) else {
                break
            }
            let marker = markerRange.lowerBound
            let head = html.startIndex..<marker
            guard let divOpen = html.range(of: "<div", options: [.backwards, .caseInsensitive], range: head)?.lowerBound else {
                searchStart = html.index(after: marker)
                continue
            }

            guard let openTagEnd = html[divOpen...].firstIndex(of: ">") else {
                searchStart = html.index(after: marker)
                continue
            }

            let contentStart = html.index(after: openTagEnd)
            guard let (inner, afterBlock) = balancedClosingDivHTML(html, contentStart: contentStart) else {
                searchStart = html.index(after: marker)
                continue
            }

            let text = htmlFragmentToLyricLines(inner)
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                pieces.append(text)
            }
            searchStart = afterBlock
        }

        return pieces.joined(separator: "\n\n")
    }

    private static func balancedClosingDivHTML(
        _ html: String,
        contentStart: String.Index
    ) -> (inner: Substring, afterClosing: String.Index)? {
        var i = contentStart
        var depth = 1

        while i < html.endIndex {
            if isClosingDivTag(html, at: i) {
                depth -= 1
                if depth == 0 {
                    let inner = html[contentStart..<i]
                    let after = html.index(i, offsetBy: 6)
                    return (inner, after)
                }
                i = html.index(i, offsetBy: 6)
                continue
            }

            if isOpeningDivTag(html, at: i) {
                guard let gt = html[i...].firstIndex(of: ">") else { break }
                depth += 1
                i = html.index(after: gt)
                continue
            }

            i = html.index(after: i)
        }
        return nil
    }

    private static func isClosingDivTag(_ html: String, at i: String.Index) -> Bool {
        guard let end = html.index(i, offsetBy: 6, limitedBy: html.endIndex) else { return false }
        return html[i..<end].caseInsensitiveCompare("</div>") == .orderedSame
    }

    private static func isOpeningDivTag(_ html: String, at i: String.Index) -> Bool {
        guard let end = html.index(i, offsetBy: 4, limitedBy: html.endIndex) else { return false }
        return html[i..<end].caseInsensitiveCompare("<div") == .orderedSame
    }

    private static func htmlFragmentToLyricLines(_ fragment: Substring) -> String {
        var s = String(fragment)
        s = s.replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "<br />", with: "\n", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "</p>", with: "\n", options: .caseInsensitive)
        s = stripHTMLTags(s)
        s = decodeAllHTMLEntities(s)
        s = s.replacingOccurrences(of: "\u{00a0}", with: " ")
        return s
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func isLikelySectionHeader(_ line: String) -> Bool {
        let trimmed = trimLineForSectionParsing(line)
        guard !trimmed.isEmpty else { return false }

        let patterns = [
            // Allow single-letter tags like `[I]` (Intro) / `[V]` (Verse) used on some pages.
            #"^\[[^\]\n]{1,200}\]$"#,
            #"^\([^)\n]{1,200}\)$"#,
            #"^(?i)(verse|chorus|refrain|hook|bridge|pre-chorus|post-chorus|outro|intro|interlude|break|instrumental|part)\b[\w\s\-:&,'/.]*$"#
        ]

        return patterns.contains { pattern in
            guard let re = try? NSRegularExpression(pattern: pattern, options: []) else { return false }
            let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            return re.firstMatch(in: trimmed, options: [], range: range) != nil
        }
    }

    private static func stripHTMLTags(_ html: String) -> String {
        var out = ""
        out.reserveCapacity(html.count)
        var i = html.startIndex
        while i < html.endIndex {
            if html[i] == "<" {
                if let close = html[i...].firstIndex(of: ">") {
                    i = html.index(after: close)
                } else {
                    out.append(html[i])
                    i = html.index(after: i)
                }
            } else {
                out.append(html[i])
                i = html.index(after: i)
            }
        }
        return out
    }

    private static func decodeAllHTMLEntities(_ s: String) -> String {
        decodeNumericHTMLEntities(
            s.replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#39;", with: "'")
                .replacingOccurrences(of: "&apos;", with: "'")
        )
    }

    /// Handles `&#39;`, `&#x27;`, etc. Run after `&amp;` so numeric codes are final.
    private static func decodeNumericHTMLEntities(_ s: String) -> String {
        var out = ""
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "&",
               let hashIdx = s.index(i, offsetBy: 1, limitedBy: s.endIndex),
               hashIdx < s.endIndex, s[hashIdx] == "#" {
                let afterHash = s.index(after: hashIdx)
                if afterHash < s.endIndex {
                    var value: UInt32?
                    var scan = afterHash
                    if s[scan] == "x" || s[scan] == "X" {
                        scan = s.index(after: scan)
                        var hex = 0 as UInt32
                        var any = false
                        while scan < s.endIndex {
                            let ch = s[scan]
                            guard let d = ch.hexDigitValue else { break }
                            hex = hex * 16 + UInt32(d)
                            any = true
                            scan = s.index(after: scan)
                        }
                        if any, scan < s.endIndex, s[scan] == ";" {
                            value = hex
                            i = s.index(after: scan)
                        }
                    } else {
                        var dec: UInt32 = 0
                        var any = false
                        while scan < s.endIndex {
                            let ch = s[scan]
                            guard let d = ch.wholeNumberValue else { break }
                            dec = dec * 10 + UInt32(d)
                            any = true
                            scan = s.index(after: scan)
                        }
                        if any, scan < s.endIndex, s[scan] == ";" {
                            value = dec
                            i = s.index(after: scan)
                        }
                    }
                    if let v = value, let scalar = UnicodeScalar(v) {
                        out.append(Character(scalar))
                        continue
                    }
                }
            }
            out.append(s[i])
            i = s.index(after: i)
        }
        return out
    }
}
