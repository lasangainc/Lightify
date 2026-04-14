//
//  ArtworkColorSampler.swift
//  Lightify
//

import AppKit
import SwiftUI

enum ArtworkColorSampler {
    /// Average RGB sampled from a downscaled bitmap, plus a darker **fully opaque** variant for gradients (no alpha fade).
    nonisolated static func tint(from imageData: Data) -> (color: Color, gradientEnd: Color, luminance: CGFloat)? {
        guard let img = NSImage(data: imageData) else { return nil }
        return tint(from: img)
    }

    nonisolated static func tint(from img: NSImage) -> (color: Color, gradientEnd: Color, luminance: CGFloat)? {
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
        let step = 4
        let w = Int(size.width)
        let h = Int(size.height)
        for y in stride(from: 0, to: h, by: step) {
            for x in stride(from: 0, to: w, by: step) {
                guard let c = rep.colorAt(x: x, y: y) else { continue }
                var rr: CGFloat = 0
                var gg: CGFloat = 0
                var bb: CGFloat = 0
                c.usingColorSpace(.deviceRGB)?.getRed(&rr, green: &gg, blue: &bb, alpha: nil)
                r += rr
                g += gg
                b += bb
                count += 1
            }
        }
        guard count > 0 else { return nil }
        r /= CGFloat(count)
        g /= CGFloat(count)
        b /= CGFloat(count)
        let luma = 0.299 * r + 0.587 * g + 0.114 * b
        let scale: CGFloat = 0.58
        let er = min(max(r * scale, 0), 1)
        let eg = min(max(g * scale, 0), 1)
        let eb = min(max(b * scale, 0), 1)
        let gradientEnd = Color(red: er, green: eg, blue: eb)
        return (Color(red: r, green: g, blue: b), gradientEnd, luma)
    }
}
