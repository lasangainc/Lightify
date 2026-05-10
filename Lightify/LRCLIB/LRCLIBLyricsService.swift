//
//  LRCLIBLyricsService.swift
//  Lightify
//
//  Fetches lyrics from https://lrclib.net (no API key). Uses GET /api/get with track signature,
//  then falls back to /api/search when no exact match exists. Parses LRC `syncedLyrics` for timing.
//

import Foundation

enum LRCLIBLyricsError: Error, LocalizedError, Sendable {
    case notFound
    case emptyLyrics
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "We couldn't find the lyrics for this one."
        case .emptyLyrics:
            return "This track has no readable lyrics in LRCLIB yet."
        case .invalidResponse:
            return "Unexpected response from LRCLIB."
        case .httpStatus(let code):
            return "Request failed (HTTP \(code))."
        }
    }
}

struct SyncedLyricLine: Identifiable, Sendable, Equatable {
    let id: Int
    let startMs: Int
    let text: String
}

struct LRCLIBFetchedLyrics: Sendable, Equatable {
    var plainText: String
    var syncedLines: [SyncedLyricLine]?
    var instrumental: Bool
}

struct LRCLIBLyricsService: Sendable {
    private let session: URLSession
    private let baseURL = URL(string: "https://lrclib.net")!

    nonisolated init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchLyrics(trackName: String, artistName: String, albumName: String?, durationMs: Int) async throws -> LRCLIBFetchedLyrics {
        let titleT = Self.cleanTitle(trackName)
        let artistT = Self.cleanArtist(artistName, pairedWithTitle: trackName)
        let albumT = albumName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Unknown Album"
        let durationSec = max(1, durationMs / 1000)

        guard !titleT.isEmpty, !artistT.isEmpty else {
            throw LRCLIBLyricsError.notFound
        }

        if let record = try await getBySignature(
            trackName: titleT,
            artistName: artistT,
            albumName: albumT,
            durationSec: durationSec
        ) {
            return Self.fetched(from: record)
        }

        if let record = try await searchFallback(
            trackName: titleT,
            artistName: artistT,
            albumName: albumT,
            durationSec: durationSec
        ) {
            return Self.fetched(from: record)
        }

        throw LRCLIBLyricsError.notFound
    }

    // MARK: - Network

    private func getBySignature(
        trackName: String,
        artistName: String,
        albumName: String,
        durationSec: Int
    ) async throws -> LRCLIBRecordDTO? {
        var c = URLComponents(url: baseURL.appendingPathComponent("api/get"), resolvingAgainstBaseURL: false)!
        c.queryItems = [
            URLQueryItem(name: "track_name", value: trackName),
            URLQueryItem(name: "artist_name", value: artistName),
            URLQueryItem(name: "album_name", value: albumName),
            URLQueryItem(name: "duration", value: String(durationSec)),
        ]
        guard let url = c.url else { return nil }
        return try await requestRecord(url: url, acceptNotFound: true)
    }

    private func searchFallback(
        trackName: String,
        artistName: String,
        albumName: String,
        durationSec: Int
    ) async throws -> LRCLIBRecordDTO? {
        var c = URLComponents(url: baseURL.appendingPathComponent("api/search"), resolvingAgainstBaseURL: false)!
        c.queryItems = [
            URLQueryItem(name: "track_name", value: trackName),
            URLQueryItem(name: "artist_name", value: artistName),
        ]
        guard let url = c.url else { return nil }
        let records = try await requestSearchArray(url: url)
        return Self.pickSearchMatch(records: records, durationSec: durationSec, trackName: trackName, artistName: artistName, albumName: albumName)
    }

    private func requestRecord(url: URL, acceptNotFound: Bool) async throws -> LRCLIBRecordDTO? {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404, acceptNotFound { return nil }
        guard status == 200 else {
            throw LRCLIBLyricsError.httpStatus(status)
        }
        let decoder = JSONDecoder()
        return try decoder.decode(LRCLIBRecordDTO.self, from: data)
    }

    private func requestSearchArray(url: URL) async throws -> [LRCLIBRecordDTO] {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw LRCLIBLyricsError.httpStatus(status)
        }
        let decoder = JSONDecoder()
        return try decoder.decode([LRCLIBRecordDTO].self, from: data)
    }

    private static let userAgent: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1"
        return "Lightify/\(version) (wss.Lightify)"
    }()

    // MARK: - Match + parse

    private static func fetched(from record: LRCLIBRecordDTO) -> LRCLIBFetchedLyrics {
        let plain = record.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let syncedRaw = record.syncedLyrics?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let parsed = syncedRaw.isEmpty ? [] : LRCLIBLRCParser.parse(syncedLRC: syncedRaw)
        let synced: [SyncedLyricLine]? = parsed.isEmpty ? nil : parsed
        let instrumental = record.instrumental == true
        return LRCLIBFetchedLyrics(plainText: plain, syncedLines: synced, instrumental: instrumental)
    }

    private static func pickSearchMatch(
        records: [LRCLIBRecordDTO],
        durationSec: Int,
        trackName: String,
        artistName: String,
        albumName: String
    ) -> LRCLIBRecordDTO? {
        guard !records.isEmpty else { return nil }
        let tLower = trackName.lowercased()
        let aLower = artistName.lowercased()
        let albLower = albumName.lowercased()

        func score(_ r: LRCLIBRecordDTO) -> Int {
            let durDelta = abs(r.duration - durationSec)
            var s = 10_000 - min(durDelta, 120) * 40
            if let syn = r.syncedLyrics, !syn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                s += 800
            } else if let pl = r.plainLyrics, !pl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                s += 200
            }
            let rt = r.trackName.lowercased()
            if rt == tLower { s += 500 }
            else if rt.contains(tLower) || tLower.contains(rt) { s += 220 }
            let ra = r.artistName.lowercased()
            if ra == aLower { s += 400 }
            else if ra.contains(aLower) || aLower.contains(ra) { s += 180 }
            if let al = r.albumName?.lowercased(), al == albLower { s += 150 }
            return s
        }

        return records.max(by: { score($0) < score($1) })
    }

    private static func cleanTitle(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let cutMarkers = [
            " (feat.", " (featuring ", " (ft.", " (with ", " [feat.", " feat.",
        ]
        for m in cutMarkers {
            if let r = t.range(of: m, options: .caseInsensitive) {
                t = String(t[..<r.lowerBound])
            }
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanArtist(_ raw: String, pairedWithTitle title: String) -> String {
        var a = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleHadFeat =
            title.range(of: "feat.", options: .caseInsensitive) != nil
            || title.range(of: "featuring", options: .caseInsensitive) != nil
            || title.range(of: "(ft.", options: .caseInsensitive) != nil
        if titleHadFeat, let comma = a.firstIndex(of: ",") {
            let head = a[..<comma].trimmingCharacters(in: .whitespacesAndNewlines)
            if !head.isEmpty { a = head }
        }
        return a
            .components(separatedBy: "+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

// MARK: - DTO

private struct LRCLIBRecordDTO: Decodable, Sendable {
    let id: Int
    let trackName: String
    let artistName: String
    let albumName: String?
    let duration: Int
    let instrumental: Bool?
    let plainLyrics: String?
    let syncedLyrics: String?
}

// MARK: - LRC

private enum LRCLIBLRCParser {
    private static let lineTimePrefix = try! NSRegularExpression(
        pattern: #"^\[(\d+):(\d{2})(?:\.(\d{1,3}))?\]\s*"#,
        options: []
    )

    static func parse(syncedLRC: String) -> [SyncedLyricLine] {
        var result: [SyncedLyricLine] = []
        var idCounter = 0
        for raw in syncedLRC.components(separatedBy: .newlines) {
            var remainder = raw
            var firstStart: Int?
            while true {
                let ns = remainder.startIndex == remainder.endIndex
                    ? NSRange(location: 0, length: 0)
                    : NSRange(remainder.startIndex..<remainder.endIndex, in: remainder)
                guard let match = lineTimePrefix.firstMatch(in: remainder, options: [], range: ns), match.range.location == 0 else {
                    break
                }
                let minR = Range(match.range(at: 1), in: remainder)!
                let secR = Range(match.range(at: 2), in: remainder)!
                let ms = startMs(minutes: String(remainder[minR]), seconds: String(remainder[secR]), fraction: match.range(at: 3).location != NSNotFound ? String(remainder[Range(match.range(at: 3), in: remainder)!]) : nil)
                if firstStart == nil { firstStart = ms }
                remainder = String(remainder[Range(match.range, in: remainder)!.upperBound...])
            }
            let text = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let start = firstStart, !text.isEmpty else { continue }
            result.append(SyncedLyricLine(id: idCounter, startMs: start, text: text))
            idCounter += 1
        }
        return result.sorted { $0.startMs < $1.startMs }
    }

    private static func startMs(minutes: String, seconds: String, fraction: String?) -> Int {
        let m = Int(minutes) ?? 0
        let s = Int(seconds) ?? 0
        var frac = 0.0
        if let f = fraction, !f.isEmpty, let v = Double(f) {
            if f.count >= 3 {
                frac = v / 1000.0
            } else {
                frac = v / 100.0
            }
        }
        let totalSec = Double(m * 60 + s) + frac
        return Int((totalSec * 1000.0).rounded())
    }
}
