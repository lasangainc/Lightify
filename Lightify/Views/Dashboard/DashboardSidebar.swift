//
//  DashboardSidebar.swift
//  Lightify
//

import SwiftUI

struct DashboardSidebar: View {
    @Environment(AppSession.self) private var appSession

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    sidebarRow(
                        title: "Home",
                        systemImage: "house.fill",
                        selection: .home
                    )
                    sidebarRow(
                        title: "Liked Songs",
                        systemImage: "music.note.list",
                        selection: .likedSongs
                    )
                    sidebarRow(
                        title: "Search",
                        systemImage: "magnifyingglass",
                        selection: .search
                    )
                } header: {
                    Text("Library")
                }

                Section {
                    newPlaylistSidebarRow
                    ForEach(accessiblePlaylists) { playlist in
                        sidebarRow(
                            title: playlist.name,
                            systemImage: "music.note.list",
                            selection: .playlist(id: playlist.id)
                        )
                    }
                } header: {
                    Text("Playlists")
                }
            }

            Divider()

            sidebarProfileFooter
        }
        .navigationTitle("Library")
    }

    private var accessiblePlaylists: [SpotifyPlaylistItem] {
        appSession.playlists.filter { !$0.isLikelyLikedSongsMirror }
    }

    private var newPlaylistSidebarRow: some View {
        Button {
            appSession.presentNewPlaylistSheet()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.secondary)
                Text("New Playlist")
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
        .listRowBackground(Color.clear)
    }

    private func sidebarRow(title: String, systemImage: String, selection: AppSession.LibrarySelection) -> some View {
        Button {
            Task { await appSession.selectLibrary(selection) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundStyle(isSelected(selection) ? .white : .secondary)
                Text(title)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected(selection) ? Color("AccentColor") : Color.clear)
            )
            .foregroundStyle(isSelected(selection) ? .white : .primary)
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
        .listRowBackground(Color.clear)
    }

    private var sidebarProfileFooter: some View {
        Button {
            Task { await appSession.selectLibrary(.profile) }
        } label: {
            HStack(spacing: 10) {
                DashboardProfileAvatar(size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(appSession.currentUserProfile?.resolvedDisplayName ?? "Spotify")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text("View profile")
                        .font(.caption)
                        .foregroundStyle(isSelected(.profile) ? .white.opacity(0.88) : .secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected(.profile) ? Color("AccentColor") : Color(nsColor: .controlBackgroundColor))
            )
            .foregroundStyle(isSelected(.profile) ? .white : .primary)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    private func isSelected(_ selection: AppSession.LibrarySelection) -> Bool {
        appSession.selectedLibrary == selection
    }
}

/// Shared avatar component used by both the sidebar footer and the profile section.
struct DashboardProfileAvatar: View {
    @Environment(AppSession.self) private var appSession
    let size: CGFloat

    var body: some View {
        RemoteArtworkImage(url: appSession.currentUserProfile?.profileImageURL, maxPixelSize: size * 2) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            Circle()
                .fill(Color.secondary.opacity(0.2))
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
