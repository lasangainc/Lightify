//
//  LightifyApp.swift
//  Lightify
//

import SwiftUI

@main
struct LightifyApp: App {
    @State private var appSession = AppSession()
    @State private var playback = PlaybackViewModel()

    var body: some Scene {
        WindowGroup(id: MainWindowScene.id) {
            ContentView()
                .environment(appSession)
                .environment(playback)
                .tint(Color("AccentColor"))
                .onAppear {
                    playback.attach(appSession: appSession)
                }
        }

        Window("Mini Player", id: MiniPlayerWindowScene.id) {
            MiniPlayerWindowView()
                .environment(appSession)
                .environment(playback)
                .tint(Color("AccentColor"))
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(
            width: MiniPlayerWindowMetrics.compact.width,
            height: MiniPlayerWindowMetrics.compact.height
        )
    }
}
