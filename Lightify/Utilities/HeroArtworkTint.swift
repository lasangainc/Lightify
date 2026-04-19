//
//  HeroArtworkTint.swift
//  Lightify
//

import AppKit
import SwiftUI

/// Shared artwork tint logic for playlist/album hero gradients and artist avatar glow.
/// Light mode: closest semantic `NSColor.system*` hue to the artwork (same as `LibraryHeroGradient`).
/// Dark mode: mean color + darkened partner from `ArtworkColorSampler`.
enum HeroArtworkTint {
    /// Semantic system colors used for light-mode hero gradients (closest-hue match to artwork).
    static let systemHeroCandidateColors: [NSColor] = [
        .systemRed, .systemOrange, .systemYellow, .systemGreen,
        .systemMint, .systemTeal, .systemCyan, .systemBlue,
        .systemIndigo, .systemPurple, .systemPink,
    ]

    /// Primary and gradient-end colors for blurred hero washes and glows.
    static func tintStop(for palette: ArtworkPalette, colorScheme: ColorScheme) -> (color: Color, gradientEnd: Color) {
        if colorScheme == .light {
            return nearestSystemHeroStops(from: palette)
        }
        return (palette.average, palette.averageDark)
    }

    /// Liked Songs hero: map each crossfade layer to a distinct system color, spread across the full palette (both appearances).
    static func systemHeroStopsForLikedLayer(index: Int, layerCount: Int) -> (color: Color, gradientEnd: Color) {
        let n = systemHeroCandidateColors.count
        let colorIdx: Int
        if layerCount <= 1 {
            colorIdx = 0
        } else {
            colorIdx = (index * (n - 1)) / (layerCount - 1)
        }
        let ns = systemHeroCandidateColors[colorIdx]
        return (Color(nsColor: ns), heroDarkenedGradientEnd(from: ns))
    }

    // MARK: - Private

    /// Darkened RGB stop matching `ArtworkColorSampler`’s `averageDark` scale (0.58).
    private static func heroDarkenedGradientEnd(from nsColor: NSColor) -> Color {
        let rgb = nsColor.usingColorSpace(.deviceRGB) ?? nsColor
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        rgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        let darkScale: CGFloat = 0.58
        return Color(
            red: min(max(r * darkScale, 0), 1),
            green: min(max(g * darkScale, 0), 1),
            blue: min(max(b * darkScale, 0), 1),
            opacity: a
        )
    }

    private static func nearestSystemHeroStops(from palette: ArtworkPalette) -> (color: Color, gradientEnd: Color) {
        let reference = palette.vibrant?.color ?? palette.average
        let ns = NSColor(reference)
        let rgb = ns.usingColorSpace(.deviceRGB) ?? ns
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        if s < 0.12 {
            let gray = NSColor.systemGray
            return (Color(nsColor: gray), heroDarkenedGradientEnd(from: gray))
        }
        var best = NSColor.systemBlue
        var bestHueDist = CGFloat.greatestFiniteMagnitude
        for candidate in systemHeroCandidateColors {
            let cRGB = candidate.usingColorSpace(.deviceRGB) ?? candidate
            var ch: CGFloat = 0
            var cs: CGFloat = 0
            var cb: CGFloat = 0
            var ca: CGFloat = 0
            cRGB.getHue(&ch, saturation: &cs, brightness: &cb, alpha: &ca)
            let delta = abs(h - ch)
            let hueDist = min(delta, 1 - delta)
            if hueDist < bestHueDist {
                bestHueDist = hueDist
                best = candidate
            }
        }
        return (Color(nsColor: best), heroDarkenedGradientEnd(from: best))
    }
}
