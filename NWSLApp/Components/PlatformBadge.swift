//
//  PlatformBadge.swift
//  NWSLApp
//
//  The small rounded-square platform glyph shared by every content card (YouTube
//  meta row, Bluesky headers, the social-clip + reddit attributions, the article
//  favicon). One source of truth for each platform's brand color + glyph, so the
//  badge reads the same everywhere.
//
//  Fidelity choice: SF Symbols where they're crisp (YouTube play, article
//  newspaper, reddit a bold "R"); for Bluesky/TikTok/Instagram the closest SF
//  Symbol (bubble / music note / camera) over an off-brand emoji. The shape is
//  cornerRadius = size·0.3, the glyph fontSize = size·0.55, white + bold — scaled
//  off the passed size so a 13/14/18/20pt badge all look right.
//

import SwiftUI

struct PlatformBadge: View {
    let platform: ContentCard.Platform
    var size: CGFloat = 14

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(fill)
            .frame(width: size, height: size)
            .overlay { glyph }
    }

    /// Brand fill from the single `PlatformBrand` source (Instagram is a gradient).
    private var fill: AnyShapeStyle {
        switch platform {
        case .instagram: return PlatformBrand.instagram
        case .youtube:   return PlatformBrand.youtube
        case .bluesky:   return PlatformBrand.bluesky
        case .tiktok:    return PlatformBrand.tiktok
        case .article:   return PlatformBrand.article
        case .reddit:    return PlatformBrand.reddit
        }
    }

    @ViewBuilder
    private var glyph: some View {
        if platform == .reddit {
            // Reddit reads best as its wordmark "R", not a symbol.
            Text("R")
                .dsFont(size * 0.62, weight: .heavy)
                .foregroundStyle(.white)
        } else {
            Image(systemName: symbolName)
                .dsFont(size * 0.55, weight: .bold)
                .foregroundStyle(.white)
        }
    }

    private var symbolName: String {
        switch platform {
        case .youtube:   return "play.fill"
        case .bluesky:   return "bubble.left.fill"
        case .tiktok:    return "music.note"
        case .instagram: return "camera.fill"
        case .article:   return "newspaper.fill"
        case .reddit:    return "r.circle.fill"   // unused (reddit draws "R")
        }
    }
}

#Preview {
    HStack(spacing: 12) {
        PlatformBadge(platform: .youtube, size: 24)
        PlatformBadge(platform: .bluesky, size: 24)
        PlatformBadge(platform: .tiktok, size: 24)
        PlatformBadge(platform: .instagram, size: 24)
        PlatformBadge(platform: .article, size: 24)
        PlatformBadge(platform: .reddit, size: 24)
    }
    .padding()
    .background(Color.dsBgGrouped)
}
