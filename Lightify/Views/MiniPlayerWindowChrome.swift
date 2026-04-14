//
//  MiniPlayerWindowChrome.swift
//  Lightify
//

import AppKit
import SwiftUI

/// Hides the title bar and keeps the window **opaque** so nothing behind the window shows through.
struct MiniPlayerWindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = false
            window.styleMask.insert(.fullSizeContentView)
            window.isOpaque = true
            window.backgroundColor = .underPageBackgroundColor
            /// Never participate in window restoration; keeps the mini player from reappearing after quit.
            window.isRestorable = false
        }
    }
}
