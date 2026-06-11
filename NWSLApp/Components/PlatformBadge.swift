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
            .overlay {
                // TikTok's badge is black — a hairline keeps it from vanishing on
                // the dark card.
                if platform == .tiktok {
                    RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                        .stroke(Color(hex: "#333333"), lineWidth: 1)
                }
            }
    }

    private var fill: AnyShapeStyle {
        switch platform {
        case .instagram:
            // Instagram's 45° brand gradient (purple → magenta → amber).
            return AnyShapeStyle(LinearGradient(
                colors: [Color(hex: "#515BD4"), Color(hex: "#8134AF"),
                         Color(hex: "#DD2A7B"), Color(hex: "#FEDA77")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
        case .youtube:   return AnyShapeStyle(Color(hex: "#FF0000"))
        case .bluesky:   return AnyShapeStyle(Color(hex: "#0085FF"))
        case .tiktok:    return AnyShapeStyle(Color(hex: "#000000"))
        case .article:   return AnyShapeStyle(Color(hex: "#636366"))
        case .reddit:    return AnyShapeStyle(Color(hex: "#FF4500"))
        }
    }

    @ViewBuilder
    private var glyph: some View {
        if platform == .reddit {
            // Reddit reads best as its wordmark "R", not a symbol.
            Text("R")
                .font(.system(size: size * 0.62, weight: .heavy))
                .foregroundStyle(.white)
        } else {
            Image(systemName: symbolName)
                .font(.system(size: size * 0.55, weight: .bold))
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
