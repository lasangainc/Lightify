//
//  PlaybackScrubber.swift
//  Lightify
//

import SwiftUI

struct PlaybackScrubber: View {
    let positionMs: Int
    let durationMs: Int
    let isEnabled: Bool
    /// Track / unfilled segment (mini player passes adaptive colors; main player keeps defaults).
    var trackColor: Color = .white.opacity(0.14)
    var progressColor: Color = Color("AccentColor")
    let onSeek: (Int) -> Void

    @State private var dragFraction: Double?

    var body: some View {
        GeometryReader { proxy in
            let progressFraction = displayedFraction

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(trackColor)
                    .frame(height: 3)

                Capsule()
                    .fill(progressColor.opacity(isEnabled ? 0.9 : 0.35))
                    .frame(width: max(0, proxy.size.width * CGFloat(progressFraction)), height: 3)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard canSeek else { return }
                        dragFraction = fraction(for: value.location.x, width: proxy.size.width)
                    }
                    .onEnded { value in
                        guard canSeek else {
                            dragFraction = nil
                            return
                        }
                        let targetFraction = fraction(for: value.location.x, width: proxy.size.width)
                        dragFraction = nil
                        onSeek(Int((Double(durationMs) * targetFraction).rounded()))
                    }
            )
        }
        .frame(height: 12)
        .help(canSeek ? "Seek" : "Playback progress")
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue(accessibilityValue)
    }

    private var canSeek: Bool {
        isEnabled && durationMs > 0
    }

    private var displayedFraction: Double {
        if let dragFraction {
            return dragFraction
        }
        guard durationMs > 0 else { return 0 }
        return min(max(Double(positionMs) / Double(durationMs), 0), 1)
    }

    private var accessibilityValue: String {
        guard durationMs > 0 else { return "Unavailable" }
        return "\(formattedTime(positionMs)) of \(formattedTime(durationMs))"
    }

    private func fraction(for xPosition: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        let clampedX = min(max(xPosition, 0), width)
        return Double(clampedX / width)
    }

    private func formattedTime(_ milliseconds: Int) -> String {
        let totalSeconds = max(milliseconds / 1000, 0)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
