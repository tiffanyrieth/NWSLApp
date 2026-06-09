//
//  TeamLogo.swift
//  NWSLApp
//
//  Small team crest for match cards and (later) Standings / Team pages.
//  Wraps AsyncImage with a fixed frame, a loading placeholder, and a neutral
//  failure fallback so rows never reflow or show a broken-image glyph.
//
//  Extracted into Components/ on first use (MatchCard) because the same
//  logo + fallback behavior is needed by upcoming Standings and Team views —
//  one source of truth for size, placeholder, and accessibility.
//
//  Crests load through the shared in-memory ImageCache (NSCache singleton) rather
//  than a bare AsyncImage, so they aren't re-downloaded when a cell is recycled
//  during scroll. A synchronous cache hit paints on the first frame, so a
//  scrolled-back crest shows instantly with no flash.
//

import SwiftUI

/// A team crest rendered at a fixed size. Falls back to a neutral rounded
/// placeholder (never a broken-image glyph) because the team abbreviation
/// shown beside it already identifies the club.
struct TeamLogo: View {
    let urlString: String?
    var size: CGFloat = 24

    // The decoded crest, once resolved. Seeded synchronously from the cache (see
    // body) so a cached image is shown on the first frame.
    @State private var image: UIImage?

    // Guard nil/empty strings here so an absent logo goes straight to the
    // placeholder instead of spinning on an invalid URL.
    private var url: URL? {
        guard let urlString, !urlString.isEmpty else { return nil }
        return URL(string: urlString)
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                placeholder                         // loading / failure / nil URL
            }
        }
        .frame(width: size, height: size)           // fixed BEFORE load → no reflow
        .accessibilityHidden(true)                  // abbreviation already names the team
        // Keyed to the URL so a recycled cell re-targets the right crest. Seed
        // synchronously from the cache first (no flash on scroll-back), then fetch
        // only on a miss.
        .task(id: url) {
            guard let url else { image = nil; return }
            if let hit = ImageCache.shared.cached(url) {
                image = hit
                return
            }
            image = await ImageCache.shared.image(for: url)
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color(.tertiarySystemFill))
    }
}

#Preview {
    VStack(spacing: 12) {
        TeamLogo(urlString: "https://a.espncdn.com/i/teamlogos/soccer/500/example.png")
        TeamLogo(urlString: nil)            // fallback path
    }
    .padding()
}
