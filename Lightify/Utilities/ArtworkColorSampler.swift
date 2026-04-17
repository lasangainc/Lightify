//
//  ArtworkColorSampler.swift
//  Lightify
//

import AppKit
import SwiftUI

/// Palette extracted from an artwork bitmap: the flat average plus a hue-bucketed vibrant pick.
///
/// `average`/`averageDark` drive dark-mode gradients (moody wash from the mean color).
/// `vibrant` is used for light-mode gradients where the flat average collapses to muddy grey;
/// it's nil for grayscale artwork so callers can cleanly skip painting a tint.
struct ArtworkPalette {
    struct Vibrant {
        let color: Color
        let hue: CGFloat
        let saturation: CGFloat
        let brightness: CGFloat
    }

    let average: Color
    let averageDark: Color
    let luminance: CGFloat
    let vibrant: Vibrant?
}

enum ArtworkColorSampler {
    /// Average RGB sampled from a downscaled bitmap, plus a darker **fully opaque** variant for gradients (no alpha fade).
    nonisolated static func tint(from imageData: Data) -> (color: Color, gradientEnd: Color, luminance: CGFloat)? {
        guard let palette = palette(from: imageData) else { return nil }
        return (palette.average, palette.averageDark, palette.luminance)
    }

    nonisolated static func tint(from img: NSImage) -> (color: Color, gradientEnd: Color, luminance: CGFloat)? {
        guard let palette = palette(from: img) else { return nil }
        return (palette.average, palette.averageDark, palette.luminance)
    }

    nonisolated static func palette(from imageData: Data) -> ArtworkPalette? {
        guard let img = NSImage(data: imageData) else { return nil }
        return palette(from: img)
    }

    nonisolated static func palette(from img: NSImage) -> ArtworkPalette? {
        let size = CGSize(width: 64, height: 64)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 32
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        img.draw(
            in: NSRect(origin: .zero, size: size),
            from: NSRect(origin: .zero, size: img.size),
            operation: .copy,
            fraction: 1.0
        )
        NSGraphicsContext.restoreGraphicsState()

        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var count = 0

        /// 12 hue buckets give enough granularity to separate red/orange/yellow/green/etc.
        /// without fragmenting a single dominant hue across too many slots.
        let bucketCount = 12
        struct HueBucket {
            var count: Int = 0
            var sumR: CGFloat = 0
            var sumG: CGFloat = 0
            var sumB: CGFloat = 0
            var sumSat: CGFloat = 0
            var sumBright: CGFloat = 0
            var sumHueX: CGFloat = 0
            var sumHueY: CGFloat = 0
        }
        var buckets = [HueBucket](repeating: HueBucket(), count: bucketCount)

        let step = 4
        let w = Int(size.width)
        let h = Int(size.height)
        for y in stride(from: 0, to: h, by: step) {
            for x in stride(from: 0, to: w, by: step) {
                guard let raw = rep.colorAt(x: x, y: y),
                      let c = raw.usingColorSpace(.deviceRGB) else { continue }
                var rr: CGFloat = 0
                var gg: CGFloat = 0
                var bb: CGFloat = 0
                c.getRed(&rr, green: &gg, blue: &bb, alpha: nil)
                r += rr
                g += gg
                b += bb
                count += 1

                var hue: CGFloat = 0
                var sat: CGFloat = 0
                var bri: CGFloat = 0
                c.getHue(&hue, saturation: &sat, brightness: &bri, alpha: nil)

                /// Skip near-grayscale / near-black / near-white pixels so the vibrant bucket
                /// isn't dragged toward whatever neutral dominates the cover.
                if sat < 0.35 || bri < 0.22 || bri > 0.96 { continue }

                let idx = min(bucketCount - 1, Int(hue * CGFloat(bucketCount)))
                buckets[idx].count += 1
                buckets[idx].sumR += rr
                buckets[idx].sumG += gg
                buckets[idx].sumB += bb
                buckets[idx].sumSat += sat
                buckets[idx].sumBright += bri
                /// Store hue on the unit circle so averaging across the 0/1 seam works correctly.
                let angle = hue * 2 * .pi
                buckets[idx].sumHueX += cos(angle)
                buckets[idx].sumHueY += sin(angle)
            }
        }

        guard count > 0 else { return nil }
        r /= CGFloat(count)
        g /= CGFloat(count)
        b /= CGFloat(count)
        let luma = 0.299 * r + 0.587 * g + 0.114 * b
        let darkScale: CGFloat = 0.58
        let averageDark = Color(
            red: min(max(r * darkScale, 0), 1),
            green: min(max(g * darkScale, 0), 1),
            blue: min(max(b * darkScale, 0), 1)
        )

        /// Pick the hue bucket with the most saturation-weighted mass. Requires a minimum
        /// number of qualifying pixels so a single stray pixel doesn't define the tint.
        var bestIdx = -1
        var bestScore: CGFloat = 0
        for (i, bucket) in buckets.enumerated() {
            guard bucket.count >= 4 else { continue }
            let score = bucket.sumSat
            if score > bestScore {
                bestScore = score
                bestIdx = i
            }
        }

        var vibrant: ArtworkPalette.Vibrant?
        if bestIdx >= 0 {
            let bucket = buckets[bestIdx]
            let n = CGFloat(bucket.count)
            let vr = bucket.sumR / n
            let vg = bucket.sumG / n
            let vb = bucket.sumB / n
            let avgSat = bucket.sumSat / n
            let avgBright = bucket.sumBright / n
            var hueAngle = atan2(bucket.sumHueY / n, bucket.sumHueX / n)
            if hueAngle < 0 { hueAngle += 2 * .pi }
            let hue = hueAngle / (2 * .pi)
            vibrant = .init(
                color: Color(red: vr, green: vg, blue: vb),
                hue: hue,
                saturation: avgSat,
                brightness: avgBright
            )
        }

        return ArtworkPalette(
            average: Color(red: r, green: g, blue: b),
            averageDark: averageDark,
            luminance: luma,
            vibrant: vibrant
        )
    }
}
