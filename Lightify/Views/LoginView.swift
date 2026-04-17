//
//  LoginView.swift
//  Lightify
//

import AppKit
import SwiftUI

struct LoginView: View {
    @Environment(AppSession.self) private var appSession
    @State private var isSigningIn = false

    private let accent = Color("AccentColor")

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 22) {
                iconBlock

                VStack(spacing: 8) {
                    Text("Sign in")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text("Sign in to start using the best Spotify Client for Mac.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Requires Spotify Premium.")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 28)
            .padding(.top, 32)
            .padding(.bottom, 24)

            Divider()
                .opacity(0.35)

            HStack {
                Spacer()
                if isSigningIn {
                    ProgressView()
                        .controlSize(.small)
                        .frame(height: 24)
                } else {
                    Button {
                        Task {
                            isSigningIn = true
                            await appSession.signIn()
                            isSigningIn = false
                        }
                    } label: {
                        Text("Continue with Spotify")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .controlSize(.small)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(width: 400)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThickMaterial)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(0.07),
                                accent.opacity(0.02),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 28, y: 14)
        .shadow(color: accent.opacity(0.12), radius: 40, y: 8)
        .alert("Sign in", isPresented: authErrorAlertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(appSession.authError ?? "")
        }
    }

    private var authErrorAlertBinding: Binding<Bool> {
        Binding(
            get: { appSession.authError != nil },
            set: { newValue in
                if !newValue { appSession.authError = nil }
            }
        )
    }

    @ViewBuilder
    private var iconBlock: some View {
        Group {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: 80, height: 80)
        .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
    }
}

#Preview {
    LoginView()
        .environment(AppSession())
}
