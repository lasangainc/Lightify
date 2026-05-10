//
//  MiniPlayerLiquidBackdrop.swift
//  Lightify
//

import SwiftUI

/// Slow-moving blurred color masses behind the mini player artwork, driven by
/// `PlayerBackdropPalette` (k-means swatches). Not used by library playlist heroes.
struct MiniPlayerLiquidBackdrop: View {
    let palette: PlayerBackdropPalette

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                ZStack {
                    baseWash(width: w, height: h)

                    ForEach(Array(palette.swatches.enumerated()), id: \.offset) { index, color in
                        liquidBlob(
                            color: color,
                            index: index,
                            time: t,
                            width: w,
                            height: h,
                            total: palette.swatches.count
                        )
                    }

                    secondaryDriftLayer(time: t, width: w, height: h)

                    RadialGradient(
                        colors: [
                            .white.opacity(radialWhiteOpacity),
                            .clear
                        ],
                        center: .center,
                        startRadius: 24,
                        endRadius: max(w, h) * 0.55
                    )

                    LinearGradient(
                        colors: [
                            .clear,
                            .black.opacity(0.09),
                            .black.opacity(0.2)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
            }
        }
    }

    private var radialWhiteOpacity: Double {
        let l = palette.luminance
        return l < 0.5 ? 0.08 : 0.18
    }

    private func baseWash(width: CGFloat, height: CGFloat) -> some View {
        let sw = palette.swatches
        let deep = sw.first ?? Color(nsColor: .underPageBackgroundColor)
        let mid = sw.indices.contains(1) ? sw[1] : deep
        let low = sw.last ?? mid
        return LinearGradient(
            colors: [
                low.opacity(0.96),
                mid.opacity(0.9),
                deep.opacity(0.94)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func liquidBlob(
        color: Color,
        index: Int,
        time: TimeInterval,
        width: CGFloat,
        height: CGFloat,
        total: Int
    ) -> some View {
        let phase = Double(index) * 1.87 + Double(total) * 0.11
        let nx = 0.5 + 0.44 * sin(time * 0.29 + phase)
        let ny = 0.5 + 0.4 * cos(time * 0.25 + phase * 0.71)
        let wobble = 0.92 + 0.18 * sin(time * 0.17 + phase * 0.5)
        let blobW = width * wobble * 1.2
        let blobH = height * wobble * 0.88
        let blur = min(width, height) * 0.2
        let opacity = 0.36 + 0.14 * sin(time * 0.35 + Double(index) * 0.6)

        return Ellipse()
            .fill(color.opacity(opacity))
            .frame(width: blobW, height: blobH)
            .blur(radius: blur)
            .position(x: nx * width, y: ny * height)
            .blendMode(.screen)
    }

    @ViewBuilder
    private func secondaryDriftLayer(time: TimeInterval, width: CGFloat, height: CGFloat) -> some View {
        let sw = palette.swatches
        if sw.count >= 2 {
            let a = sw[sw.count - 1]
            let b = sw[0]
            let nx = 0.48 + 0.36 * cos(time * 0.21 + 0.9)
            let ny = 0.52 + 0.32 * sin(time * 0.23 + 1.4)
            let size = min(width, height) * 1.05

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [a.opacity(0.28), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: size * 0.45
                        )
                    )
                    .frame(width: size * 1.4, height: size * 1.4)
                    .blur(radius: size * 0.16)
                    .position(x: nx * width, y: ny * height)
                    .blendMode(.plusLighter)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [b.opacity(0.22), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: size * 0.4
                        )
                    )
                    .frame(width: size * 1.1, height: size * 1.1)
                    .blur(radius: size * 0.14)
                    .position(x: (1 - nx) * width * 0.92, y: (1 - ny) * height * 0.88)
                    .blendMode(.screen)
            }
        }
    }
}
