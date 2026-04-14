//
//  WebPlayerHostView.swift
//  Lightify
//

import SwiftUI
import WebKit

/// Keeps the Web Playback `WKWebView` in the view hierarchy (required for audio / EME).
struct WebPlayerHostView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.widthAnchor.constraint(equalToConstant: 2),
            webView.heightAnchor.constraint(equalToConstant: 2),
        ])
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
