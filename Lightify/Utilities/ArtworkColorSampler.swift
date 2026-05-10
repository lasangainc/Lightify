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

/// Several prominent colors from the cover (k-means on a downsampled bitmap). Used only for
/// the mini player liquid backdrop. Library playlist and album hero gradients still use
/// `ArtworkPalette` from `palette(from:)` and are intentionally unchanged.
struct PlayerBackdropPalette {
    let swatches: [Color]
    let luminance: CGFloat
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
        guard let rep = rgbBitmap(from: img, size: size) else { return nil }

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

    /// K-means palette for mini player liquid backgrounds only.
    nonisolated static func playerBackdropPalette(from imageData: Data) -> PlayerBackdropPalette? {
        guard let img = NSImage(data: imageData) else { return nil }
        return playerBackdropPalette(from: img)
    }

    nonisolated static func playerBackdropPalette(from img: NSImage) -> PlayerBackdropPalette? {
        let size = CGSize(width: 56, height: 56)
        guard let rep = rgbBitmap(from: img, size: size) else { return nil }
        return playerBackdropPalette(from: rep)
    }

    // MARK: - Private

    nonisolated private static func rgbBitmap(from img: NSImage, size: CGSize) -> NSBitmapImageRep? {
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
        return rep
    }

    nonisolated private static func playerBackdropPalette(from rep: NSBitmapImageRep) -> PlayerBackdropPalette? {
        let w = rep.pixelsWide
        let h = rep.pixelsHigh
        let step = 2
        var meanR: CGFloat = 0
        var meanG: CGFloat = 0
        var meanB: CGFloat = 0
        var meanCount = 0
        var clusterPoints: [RGBPoint] = []
        clusterPoints.reserveCapacity((w / step) * (h / step))

        for y in stride(from: 0, to: h, by: step) {
            for x in stride(from: 0, to: w, by: step) {
                guard let raw = rep.colorAt(x: x, y: y),
                      let c = raw.usingColorSpace(.deviceRGB) else { continue }
                var rr: CGFloat = 0
                var gg: CGFloat = 0
                var bb: CGFloat = 0
                var aa: CGFloat = 0
                c.getRed(&rr, green: &gg, blue: &bb, alpha: &aa)
                if aa < 0.08 { continue }
                meanR += rr
                meanG += gg
                meanB += bb
                meanCount += 1
                clusterPoints.append(RGBPoint(r: rr, g: gg, b: bb))
            }
        }

        guard meanCount > 0 else { return nil }
        meanR /= CGFloat(meanCount)
        meanG /= CGFloat(meanCount)
        meanB /= CGFloat(meanCount)
        let luma = 0.299 * meanR + 0.587 * meanG + 0.114 * meanB

        let meanPoint = RGBPoint(r: meanR, g: meanG, b: meanB)
        guard !clusterPoints.isEmpty else {
            return PlayerBackdropPalette(
                swatches: paddedSwatches(from: [meanPoint], mean: meanPoint),
                luminance: luma
            )
        }

        let k = min(5, max(3, clusterPoints.count / 18 + 1))
        var weighted = kMeansCentroids(points: clusterPoints, k: k)
        weighted = mergeSimilarCentroids(weighted, minDistanceSquared: 0.014)

        var swatches = weighted.map { Color(red: $0.centroid.r, green: $0.centroid.g, blue: $0.centroid.b) }
        if swatches.count < 3 {
            swatches = paddedSwatches(from: weighted.map(\.centroid), mean: meanPoint)
        } else if swatches.count > 5 {
            swatches = Array(swatches.prefix(5))
        }

        return PlayerBackdropPalette(swatches: swatches, luminance: luma)
    }

    nonisolated private static func paddedSwatches(from centroids: [RGBPoint], mean: RGBPoint) -> [Color] {
        var colors = centroids.map { Color(red: $0.r, green: $0.g, blue: $0.b) }
        let darkScale: CGFloat = 0.52
        let dark = Color(
            red: min(max(mean.r * darkScale, 0), 1),
            green: min(max(mean.g * darkScale, 0), 1),
            blue: min(max(mean.b * darkScale, 0), 1)
        )
        let lift = Color(
            red: min(max(mean.r * 1.08 + 0.04, 0), 1),
            green: min(max(mean.g * 1.08 + 0.04, 0), 1),
            blue: min(max(mean.b * 1.08 + 0.04, 0), 1)
        )
        while colors.count < 3 {
            if colors.isEmpty {
                colors.append(Color(red: mean.r, green: mean.g, blue: mean.b))
            } else if colors.count == 1 {
                colors.append(dark)
            } else {
                colors.append(lift)
            }
        }
        return colors
    }

    nonisolated private static func kMeansCentroids(points: [RGBPoint], k: Int) -> [(centroid: RGBPoint, weight: Int)] {
        let kClamped = min(k, points.count)
        guard kClamped > 0 else { return [] }

        var centroids: [RGBPoint] = []
        centroids.reserveCapacity(kClamped)
        for j in 0..<kClamped {
            let idx = min(points.count - 1, (j * points.count) / max(kClamped, 1))
            centroids.append(points[idx])
        }

        var assignments = [Int](repeating: 0, count: points.count)

        for _ in 0..<14 {
            for (i, p) in points.enumerated() {
                var bestJ = 0
                var bestD = CGFloat.greatestFiniteMagnitude
                for (j, c) in centroids.enumerated() {
                    let d = p.distanceSquared(to: c)
                    if d < bestD {
                        bestD = d
                        bestJ = j
                    }
                }
                assignments[i] = bestJ
            }

            var sums = [RGBPoint](repeating: .zero, count: kClamped)
            var counts = [Int](repeating: 0, count: kClamped)
            for (i, p) in points.enumerated() {
                let j = assignments[i]
                sums[j].r += p.r
                sums[j].g += p.g
                sums[j].b += p.b
                counts[j] += 1
            }

            for j in 0..<kClamped {
                if counts[j] == 0 {
                    let rescueIdx = (j * 17 + points.count / 2) % points.count
                    centroids[j] = points[rescueIdx]
                } else {
                    let n = CGFloat(counts[j])
                    centroids[j] = RGBPoint(r: sums[j].r / n, g: sums[j].g / n, b: sums[j].b / n)
                }
            }
        }

        var counts = [Int](repeating: 0, count: kClamped)
        for i in points.indices {
            counts[assignments[i]] += 1
        }

        return zip(centroids, counts)
            .sorted { $0.1 > $1.1 }
            .map { (centroid: $0.0, weight: $0.1) }
    }

    nonisolated private static func mergeSimilarCentroids(
        _ weighted: [(centroid: RGBPoint, weight: Int)],
        minDistanceSquared: CGFloat
    ) -> [(centroid: RGBPoint, weight: Int)] {
        var out: [(RGBPoint, Int)] = []
        for pair in weighted {
            if let idx = out.firstIndex(where: { outPair in
                outPair.0.distanceSquared(to: pair.centroid) < minDistanceSquared
            }) {
                let wSum = out[idx].1 + pair.weight
                let wr = (out[idx].0.r * CGFloat(out[idx].1) + pair.centroid.r * CGFloat(pair.weight)) / CGFloat(wSum)
                let wg = (out[idx].0.g * CGFloat(out[idx].1) + pair.centroid.g * CGFloat(pair.weight)) / CGFloat(wSum)
                let wb = (out[idx].0.b * CGFloat(out[idx].1) + pair.centroid.b * CGFloat(pair.weight)) / CGFloat(wSum)
                out[idx] = (RGBPoint(r: wr, g: wg, b: wb), wSum)
            } else {
                out.append((pair.centroid, pair.weight))
            }
        }
        return out.map { (centroid: $0.0, weight: $0.1) }
    }
}

// MARK: - RGB helpers (fileprivate for sampler)

private struct RGBPoint: Sendable {
    var r: CGFloat
    var g: CGFloat
    var b: CGFloat

    static let zero = RGBPoint(r: 0, g: 0, b: 0)

    func distanceSquared(to o: RGBPoint) -> CGFloat {
        let dr = r - o.r
        let dg = g - o.g
        let db = b - o.b
        return dr * dr + dg * dg + db * db
    }
}
