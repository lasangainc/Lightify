//
//  LoginView.swift
//  Lightify
//

import SwiftUI

struct LoginView: View {
    @Environment(AppSession.self) private var appSession
    @State private var isSigningIn = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "music.note.list")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("Lightify")
                .font(.largeTitle.weight(.semibold))

            Text("Connect your Spotify account for your library and liked songs. Playback streams in-app with Spotify Web Playback (Premium).")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            if let err = appSession.authError {
                Text(err)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            Button {
                Task {
                    isSigningIn = true
                    await appSession.signIn()
                    isSigningIn = false
                }
            } label: {
                if isSigningIn {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 120)
                } else {
                    Text("Log in with Spotify")
                        .frame(minWidth: 200)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSigningIn)

            Text("Set your Client ID in `SpotifyConfig.swift` and add redirect URI `lightify://oauth-callback` in the Spotify Developer Dashboard.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    LoginView()
        .environment(AppSession())
}
