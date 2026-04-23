//
//  MiniPlayerWindowChrome.swift
//  Lightify
//

import AppKit
import SwiftUI

/// Hides the title bar, keeps the window **opaque** so nothing behind the window shows through, and locks the
/// frame to `MiniPlayerWindowMetrics` (no user resizing; size tracks lyrics panel).
struct MiniPlayerWindowChrome: NSViewRepresentable {
    @Environment(PlaybackViewModel.self) private var playback

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let showsLyrics = playback.miniPlayerShowsLyricsPanel
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = false
            window.styleMask.insert(.fullSizeContentView)
            window.styleMask.remove(.resizable)
            window.isOpaque = true
            window.backgroundColor = .underPageBackgroundColor
            /// Never participate in window restoration; keeps the mini player from reappearing after quit.
            window.isRestorable = false

            let s = showsLyrics ? MiniPlayerWindowMetrics.withLyrics : MiniPlayerWindowMetrics.compact
            let nss = NSSize(width: s.width, height: s.height)
            window.contentMinSize = nss
            window.contentMaxSize = nss
        }
    }
}
