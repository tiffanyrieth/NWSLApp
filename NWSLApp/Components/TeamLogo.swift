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
//  TEMP (caching): AsyncImage has no cross-cell image cache, so logos
//  re-download every time a card is recycled during scroll. Acceptable for v1
//  (small PNGs, lazy rows). Remove this note when a shared image cache lands
//  (NSCache-backed loader or a caching layer) — tracked in CLAUDE.md
//  "What's Next".
//

import SwiftUI

/// A team crest rendered at a fixed size. Falls back to a neutral rounded
/// placeholder (never a broken-image glyph) because the team abbreviation
/// shown beside it already identifies the club.
struct TeamLogo: View {
    let urlString: String?
    var size: CGFloat = 24

    // Guard nil/empty strings here so an absent logo goes straight to the
    // placeholder instead of spinning on an invalid URL.
    private var url: URL? {
        guard let urlString, !urlString.isEmpty else { return nil }
        return URL(string: urlString)
    }

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        placeholder                 // loading
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    case .failure:
                        placeholder                 // network / decode failure
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder                         // nil / empty URL
            }
        }
        .frame(width: size, height: size)           // fixed BEFORE load → no reflow
        .accessibilityHidden(true)                  // abbreviation already names the team
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
