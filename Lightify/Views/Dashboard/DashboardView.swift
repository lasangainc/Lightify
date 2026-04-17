//
//  DashboardView.swift
//  Lightify
//

import SwiftUI

struct DashboardView: View {
    @Environment(AppSession.self) private var appSession
    @Environment(PlaybackViewModel.self) private var playback
    @State private var isRenamePlaylistAlertPresented = false
    @State private var renamePlaylistDraft = ""
    @State private var deletePlaylistTarget: SpotifyPlaylistItem?
    @State private var heroPalettes: [ArtworkPalette] = []

    var body: some View {
        NavigationSplitView {
            DashboardSidebar()
        } detail: {
            detailContent
                .navigationTitle(appSession.detailNavigationTitle)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    NowPlayingControls()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                }
        }
        .toolbar { toolbarContent }
        .sheet(isPresented: newPlaylistSheetBinding) {
            NewPlaylistSheet()
        }
        .alert("Playlist", isPresented: playlistErrorAlertBinding) {
            Button("OK") {
                appSession.playlistActionError = nil
            }
        } message: {
            Text(appSession.playlistActionError ?? "")
        }
        .alert("Error", isPresented: loadErrorAlertBinding) {
            Button("OK") {
                appSession.loadError = nil
            }
        } message: {
            Text(appSession.loadError ?? "")
        }
        .alert("Rename Playlist", isPresented: renamePlaylistAlertBinding) {
            TextField("Name", text: renamePlaylistDraftBinding)
            Button("Cancel", role: .cancel) {
                isRenamePlaylistAlertPresented = false
            }
            Button("Rename") {
                guard let playlist = selectedPlaylist else { return }
                let newName = renamePlaylistDraft
                Task {
                    let didRename = await appSession.renamePlaylist(id: playlist.id, newName: newName)
                    if didRename {
                        isRenamePlaylistAlertPresented = false
                    }
                }
            }
            .disabled(renamePlaylistDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || appSession.isMutatingSelectedPlaylist)
        } message: {
            Text("Choose a new name for this playlist.")
        }
        .confirmationDialog(
            selectedPlaylistDeleteActionTitle,
            isPresented: deletePlaylistConfirmationBinding,
            titleVisibility: .visible
        ) {
            Button(selectedPlaylistDeleteActionTitle, role: .destructive) {
                guard let playlist = deletePlaylistTarget else { return }
                Task {
                    let didDelete = await appSession.deletePlaylist(id: playlist.id)
                    if didDelete {
                        deletePlaylistTarget = nil
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                deletePlaylistTarget = nil
            }
        } message: {
            Text(selectedPlaylistDeleteMessage)
        }
    }

    // MARK: - Detail routing

    @ViewBuilder
    private var detailContent: some View {
        if case let .artist(artistID, nameHint) = appSession.selectedLibrary {
            ArtistView(artistID: artistID, nameHint: nameHint)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !playback.isWebPlayerReady {
                        Label("Connecting in-app Spotify player…", systemImage: "waveform")
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.blue.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    switch appSession.selectedLibrary {
                    case .home:
                        HomeSection()
                    case .profile:
                        ProfileSection()
                    case .likedSongs:
                        LikedSongsTrackList(
                            onRenameTapped: beginRenameSelectedPlaylist,
                            onDeleteTapped: beginDeleteSelectedPlaylist
                        )
                    case .search:
                        SearchSection()
                    case .playlist:
                        PlaylistTracksSection(
                            onRenameTapped: beginRenameSelectedPlaylist,
                            onDeleteTapped: beginDeleteSelectedPlaylist
                        )
                    case .album:
                        AlbumTracksSection(
                            onRenameTapped: beginRenameSelectedPlaylist,
                            onDeleteTapped: beginDeleteSelectedPlaylist
                        )
                    case .artist:
                        EmptyView()
                    }
                }
                .padding(20)
            }
            .background(alignment: .top) {
                LibraryHeroGradient(heroPalettes: $heroPalettes)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            if appSession.canGoBackFromAlbum {
                Button {
                    Task { await appSession.goBackFromAlbum() }
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .help("Go back")
            }
        }
        ToolbarItem(placement: .automatic) {
            Button {
                Task { await appSession.selectLibrary(.search) }
            } label: {
                Label("Search", systemImage: "magnifyingglass")
            }
            .help("Open Search")
        }
        ToolbarItem(placement: .automatic) {
            Button("Sign out", role: .destructive) {
                appSession.signOut()
            }
        }
        ToolbarItem(placement: .automatic) {
            Button("Refresh") {
                Task { await appSession.reloadLibrary() }
            }
            .disabled(appSession.phase == .loadingContent)
        }
    }

    // MARK: - Rename / delete plumbing

    private func beginRenameSelectedPlaylist() {
        renamePlaylistDraft = selectedPlaylist?.name ?? ""
        isRenamePlaylistAlertPresented = true
    }

    private func beginDeleteSelectedPlaylist() {
        deletePlaylistTarget = selectedPlaylist
    }

    private var selectedPlaylist: SpotifyPlaylistItem? {
        guard case .playlist(let id) = appSession.selectedLibrary else { return nil }
        return appSession.resolvedPlaylist(id: id)
    }

    private var selectedPlaylistCanRename: Bool {
        guard let selectedPlaylist else { return false }
        return selectedPlaylist.isOwnedByCurrentUser(appSession.currentSpotifyUserId)
    }

    private var selectedPlaylistDeleteActionTitle: String {
        selectedPlaylistCanRename ? "Delete Playlist" : "Remove from Library"
    }

    private var selectedPlaylistDeleteMessage: String {
        guard let playlist = deletePlaylistTarget else { return "This action can’t be undone." }
        if playlist.isOwnedByCurrentUser(appSession.currentSpotifyUserId) {
            return "Delete \"\(playlist.name)\" from your library? Spotify removes it by unfollowing the playlist."
        }
        return "Remove \"\(playlist.name)\" from your library?"
    }

    // MARK: - Bindings

    private var newPlaylistSheetBinding: Binding<Bool> {
        Binding(
            get: { appSession.isNewPlaylistSheetPresented },
            set: { newValue in
                if newValue {
                    appSession.isNewPlaylistSheetPresented = true
                } else {
                    appSession.dismissNewPlaylistSheet()
                }
            }
        )
    }

    /// Shows add-to-playlist failures when the create sheet isn’t visible (errors while creating stay in the sheet).
    private var playlistErrorAlertBinding: Binding<Bool> {
        Binding(
            get: { appSession.playlistActionError != nil && !appSession.isNewPlaylistSheetPresented },
            set: { newValue in
                if !newValue { appSession.playlistActionError = nil }
            }
        )
    }

    private var loadErrorAlertBinding: Binding<Bool> {
        Binding(
            get: { appSession.loadError != nil },
            set: { newValue in
                if !newValue { appSession.loadError = nil }
            }
        )
    }

    private var renamePlaylistAlertBinding: Binding<Bool> {
        Binding(
            get: { isRenamePlaylistAlertPresented && selectedPlaylist != nil },
            set: { newValue in
                isRenamePlaylistAlertPresented = newValue
                if !newValue {
                    renamePlaylistDraft = ""
                }
            }
        )
    }

    private var renamePlaylistDraftBinding: Binding<String> {
        Binding(
            get: { renamePlaylistDraft },
            set: { renamePlaylistDraft = $0 }
        )
    }

    private var deletePlaylistConfirmationBinding: Binding<Bool> {
        Binding(
            get: { deletePlaylistTarget != nil },
            set: { newValue in
                if !newValue {
                    deletePlaylistTarget = nil
                }
            }
        )
    }
}

#Preview {
    DashboardView()
        .environment(AppSession())
        .environment(PlaybackViewModel())
}
