//
//  ContentView.swift
//  Lightify
//

import AppKit
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
                loginPhaseBackdrop
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .sheet(isPresented: loginSheetPresented) {
                        LoginView()
                            .interactiveDismissDisabled()
                    }
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

    private var loginSheetPresented: Binding<Bool> {
        Binding(
            get: { appSession.phase == .needsLogin },
            set: { _ in }
        )
    }

    private var loginPhaseBackdrop: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(
                colors: [
                    Color("AccentColor").opacity(0.14),
                    Color("AccentColor").opacity(0.04),
                    .clear,
                ],
                center: .init(x: 0.5, y: 0.35),
                startRadius: 40,
                endRadius: 420
            )
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor).opacity(0),
                    Color(nsColor: .windowBackgroundColor).opacity(0.85),
                ],
                startPoint: .center,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

#Preview {
    ContentView()
        .environment(AppSession())
        .environment(PlaybackViewModel())
}
