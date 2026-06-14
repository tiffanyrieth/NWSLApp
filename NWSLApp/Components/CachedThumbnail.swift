//
//  CachedThumbnail.swift
//  NWSLApp
//
//  A drop-in replacement for `AsyncImage` on the content cards. Plain `AsyncImage`
//  re-fetches from scratch every time its view is recreated — so switching tabs and
//  coming back to Home/Feed flashes the card back to its crest fallback while the
//  frame reloads (bug #5). This seeds from the shared `ImageCache` synchronously in
//  `init`, so a recreated card paints the already-loaded frame on its first frame —
//  no flash — and only hits the network on a genuine cache miss.
//
//  The image is shown `scaledToFill`; the caller supplies the `fallback` shown until
//  (or unless) a frame is available — a crest, a gradient, or `Color.clear`.
//

import SwiftUI
import UIKit

struct CachedThumbnail<Fallback: View>: View {
    let url: URL?
    @ViewBuilder var fallback: () -> Fallback
    @State private var image: UIImage?

    init(url: URL?, @ViewBuilder fallback: @escaping () -> Fallback) {
        self.url = url
        self.fallback = fallback
        // Seed from the synchronous cache so a recycled/recreated card paints the
        // cached frame immediately, with no flash to the fallback.
        _image = State(initialValue: url.flatMap { ImageCache.shared.cached($0) })
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                fallback()
            }
        }
        // Re-keyed on url so a recycled card pointed at a new URL reloads correctly.
        .task(id: url) {
            guard image == nil, let url else { return }
            image = await ImageCache.shared.image(for: url)
        }
    }
}
