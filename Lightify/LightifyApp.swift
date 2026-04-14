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
        WindowGroup {
            ContentView()
                .environment(appSession)
                .environment(playback)
                .tint(Color("AccentColor"))
                .onAppear {
                    playback.attach(appSession: appSession)
                }
        }
    }
}
