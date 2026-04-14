//
//  RemoteArtworkImage.swift
//  Lightify
//

import SwiftUI

struct RemoteArtworkImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let maxPixelSize: CGFloat
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    @State private var resolvedImage: Image?

    var body: some View {
        Group {
            if let resolvedImage {
                content(resolvedImage)
            } else {
                placeholder()
            }
        }
        .task(id: taskID) {
            await loadImage()
        }
    }

    private var taskID: String {
        "\(url?.absoluteString ?? "nil")#\(Int(maxPixelSize.rounded(.up)))"
    }

    @MainActor
    private func loadImage() async {
        guard let url else {
            resolvedImage = nil
            return
        }

        resolvedImage = nil
        do {
            let image = try await ArtworkPipeline.shared.image(for: url, maxPixelSize: maxPixelSize)
            guard !Task.isCancelled else { return }
            resolvedImage = Image(nsImage: image)
        } catch {
            guard !Task.isCancelled else { return }
            resolvedImage = nil
        }
    }
}
