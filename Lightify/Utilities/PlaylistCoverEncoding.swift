//
//  PlaylistCoverEncoding.swift
//  Lightify
//
//  Prepares JPEG data for Spotify’s `PUT /v1/playlists/{id}/images` (base64 body, max 256 KB).
//

import AppKit
import Foundation

enum PlaylistCoverEncodingError: LocalizedError {
    case couldNotLoadImage
    case couldNotProduceJPEG

    var errorDescription: String? {
        switch self {
        case .couldNotLoadImage:
            return "Could not load the selected image."
        case .couldNotProduceJPEG:
            return "Could not compress the image as JPEG for Spotify."
        }
    }
}

enum PlaylistCoverEncoding {
    /// Spotify documents a **256 KB** maximum payload; the upload body is base64(JPEG) as UTF-8.
    private static let maxBase64PayloadBytes = 256 * 1024

    static func jpegDataForSpotifyUpload(fromFileURL url: URL) throws -> Data {
        guard let image = NSImage(contentsOf: url) else {
            throw PlaylistCoverEncodingError.couldNotLoadImage
        }
        return try jpegDataForSpotifyUpload(from: image)
    }

    static func jpegDataForSpotifyUpload(from image: NSImage) throws -> Data {
        var maxSide: CGFloat = 720

        for _ in 0 ..< 10 {
            let scaled = image.resizedToFit(maxPixelSide: maxSide)

            let compressionFactors: [CGFloat] = [0.92, 0.85, 0.78, 0.7, 0.62, 0.55, 0.48, 0.4]

            for factor in compressionFactors {
                guard let jpeg = jpegData(from: scaled, compressionFactor: factor) else { continue }
                let base64Len = jpeg.base64EncodedString().utf8.count
                if base64Len <= maxBase64PayloadBytes {
                    return jpeg
                }
            }

            maxSide *= 0.82
            if maxSide < 64 { break }
        }

        throw PlaylistCoverEncodingError.couldNotProduceJPEG
    }

    private static func jpegData(from image: NSImage, compressionFactor: CGFloat) -> Data? {
        guard
            let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: compressionFactor])
    }
}

private extension NSImage {
    func resizedToFit(maxPixelSide: CGFloat) -> NSImage {
        let w = size.width
        let h = size.height
        guard w > 0, h > 0 else { return self }
        let scale = min(maxPixelSide / max(w, h), 1)
        guard scale < 1 else { return self }

        let newSize = NSSize(width: w * scale, height: h * scale)
        let img = NSImage(size: newSize)
        img.lockFocus()
        defer { img.unlockFocus() }
        draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: size),
            operation: .copy,
            fraction: 1
        )
        return img
    }
}
