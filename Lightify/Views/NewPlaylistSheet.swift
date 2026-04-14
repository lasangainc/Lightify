//
//  NewPlaylistSheet.swift
//  Lightify
//

import SwiftUI
import UniformTypeIdentifiers

struct NewPlaylistSheet: View {
    @Environment(AppSession.self) private var appSession

    @State private var name: String = ""
    @State private var isPublic: Bool = true
    @State private var descriptionText: String = ""
    @State private var coverFileURL: URL?
    @State private var isPickingCover = false
    @FocusState private var nameFieldFocused: Bool

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)
            scrollContent
            Divider().opacity(0.3)
            footer
        }
        .frame(width: 420, height: 400)
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onAppear { nameFieldFocused = true }
        .fileImporter(
            isPresented: $isPickingCover,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result {
                coverFileURL = urls.first
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        Text("New Playlist")
            .font(.headline)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Content

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                nameField
                visibilityPicker
                descriptionField
                coverSection

                if let pending = appSession.pendingTrackForNewPlaylist {
                    pendingTrackBanner(pending)
                }

                if let err = appSession.playlistActionError {
                    Text(err)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(20)
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Name")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            TextField("My awesome playlist", text: $name)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(nameFieldFocused ? Color("AccentColor") : .white.opacity(0.1), lineWidth: 1)
                )
                .focused($nameFieldFocused)
                .onSubmit { if canCreate { createPlaylist() } }
        }
    }

    private var visibilityPicker: some View {
        HStack {
            Text("Visibility")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            Picker("", selection: $isPublic) {
                Text("Public").tag(true)
                Text("Private").tag(false)
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
        }
    }

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Description")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            TextField("Optional", text: $descriptionText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2 ... 4)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                )
        }
    }

    private var coverSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cover art")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                coverThumbnail

                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        isPickingCover = true
                    } label: {
                        Text(coverFileURL == nil ? "Choose image…" : "Change image…")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(.white.opacity(0.08))
                            .clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    if coverFileURL != nil {
                        Button {
                            coverFileURL = nil
                        } label: {
                            Text("Remove")
                                .font(.caption)
                                .foregroundStyle(.red.opacity(0.85))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer(minLength: 0)
            }

            Text("Leave blank for Spotify's automatic artwork.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var coverThumbnail: some View {
        let side: CGFloat = 56
        if let url = coverFileURL, let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFill()
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(0.06))
                .frame(width: side, height: side)
                .overlay {
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundStyle(.quaternary)
                }
        }
    }

    private func pendingTrackBanner(_ track: SpotifyTrack) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "music.note")
                .foregroundStyle(Color("AccentColor"))
            Text("\u{201C}\(track.name)\u{201D} will be added after creation.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color("AccentColor").opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") {
                appSession.dismissNewPlaylistSheet()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(appSession.isCreatingPlaylist)

            if appSession.isCreatingPlaylist {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 72, height: 32)
            } else {
                Button {
                    createPlaylist()
                } label: {
                    Text("Create")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(canCreate ? .white : .white.opacity(0.4))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 7)
                        .background(canCreate ? Color("AccentColor") : Color("AccentColor").opacity(0.35))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canCreate)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Actions

    private func createPlaylist() {
        Task {
            _ = await appSession.createPlaylistFromSheet(
                name: name,
                isPublic: isPublic,
                description: descriptionText.isEmpty ? nil : descriptionText,
                coverFileURL: coverFileURL
            )
        }
    }
}
