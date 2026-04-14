//
//  ArtworkPipeline.swift
//  Lightify
//

import AppKit
import Foundation
import ImageIO

actor ArtworkPipeline {
    static let shared = ArtworkPipeline()

    private let session: URLSession
    private let imageCache = NSCache<NSString, NSImage>()
    private let dataCache = NSCache<NSURL, NSData>()
    private var imageTasks: [NSString: Task<NSImage, Error>] = [:]
    private var dataTasks: [NSURL: Task<Data, Error>] = [:]

    private init() {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .useProtocolCachePolicy
        config.urlCache = URLCache(
            memoryCapacity: 24 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024
        )
        config.httpMaximumConnectionsPerHost = 6
        session = URLSession(configuration: config)

        imageCache.countLimit = 160
        imageCache.totalCostLimit = 32 * 1024 * 1024
        dataCache.countLimit = 96
        dataCache.totalCostLimit = 12 * 1024 * 1024
    }

    func image(for url: URL, maxPixelSize: CGFloat) async throws -> NSImage {
        let normalizedSize = max(32, Int(maxPixelSize.rounded(.up)))
        let key = NSString(string: "\(url.absoluteString)#\(normalizedSize)")
        if let cached = imageCache.object(forKey: key) {
            return cached
        }
        if let inFlight = imageTasks[key] {
            return try await inFlight.value
        }

        let task = Task<NSImage, Error> {
            let data = try await self.data(for: url)
            guard let image = Self.downsampledImage(from: data, maxPixelSize: normalizedSize) else {
                throw CocoaError(.coderInvalidValue)
            }
            let cost = max(1, normalizedSize * normalizedSize * 4)
            await self.storeImage(image, for: key, cost: cost)
            return image
        }

        imageTasks[key] = task
        defer { imageTasks.removeValue(forKey: key) }
        return try await task.value
    }

    private func data(for url: URL) async throws -> Data {
        let key = url as NSURL
        if let cached = dataCache.object(forKey: key) {
            return Data(referencing: cached)
        }
        if let inFlight = dataTasks[key] {
            return try await inFlight.value
        }

        let task = Task<Data, Error> {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            await self.storeData(data, for: key)
            return data
        }

        dataTasks[key] = task
        defer { dataTasks.removeValue(forKey: key) }
        return try await task.value
    }

    private func storeImage(_ image: NSImage, for key: NSString, cost: Int) {
        imageCache.setObject(image, forKey: key, cost: cost)
    }

    private func storeData(_ data: Data, for key: NSURL) {
        dataCache.setObject(data as NSData, forKey: key, cost: data.count)
    }

    private static func downsampledImage(from data: Data, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
