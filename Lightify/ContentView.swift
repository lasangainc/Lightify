//
//  ContentView.swift
//  Lightify
//

import SwiftUI

struct ContentView: View {
    @Environment(AppSession.self) private var appSession
    @Environment(PlaybackViewModel.self) private var playback

    var body: some View {
        Group {
            switch appSession.phase {
            case .bootstrapping:
                ProgressView("Starting…")
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .needsLogin:
                LoginView()
            case .loadingContent:
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Loading your music…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .ready:
                DashboardView()
            }
        }
        .task {
            await appSession.bootstrap()
        }
        .task(id: appSession.phase) {
            if appSession.phase == .needsLogin {
                playback.teardownWebPlayback()
            } else if appSession.phase == .ready {
                playback.startWebPlaybackEngineIfNeeded()
            }
        }
        .background(alignment: .topLeading) {
            if appSession.phase == .ready {
                WebPlayerHostView(webView: playback.webPlayerView)
                    .frame(width: 2, height: 2)
                    .allowsHitTesting(false)
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(AppSession())
        .environment(PlaybackViewModel())
}
