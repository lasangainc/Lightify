//
//  LoginView.swift
//  Lightify
//

import AppKit
import SwiftUI

struct LoginView: View {
    @Environment(AppSession.self) private var appSession
    @State private var isSigningIn = false

    var body: some View {
        VStack(spacing: 24) {
            Group {
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                }
            }
            .frame(width: 80, height: 80)
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)

            Text("Lightify")
                .font(.largeTitle.weight(.semibold))

            Text("Sign in to start using the best Spotify Client for Mac. Requires Spotify Premium.")
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
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    LoginView()
        .environment(AppSession())
}
