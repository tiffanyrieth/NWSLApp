//
//  TeamContentCard.swift
//  NWSLApp
//
//  One item in Home's Module 1 ("From your teams") — a thumbnail-forward,
//  IG/YouTube-style content card (per Reference/Design/home-tab-design-spec.md):
//  a 16:9 thumbnail on top, then an attribution line (team crest + name +
//  timestamp), the caption, and a "via YouTube/Instagram/…" source tag. The whole
//  card opens the team's channel/profile (Environment openURL), like FeedCard.
//
//  Thumbnail: YouTube items load their real frame via AsyncImage over
//  `item.thumbnailURL` (built from the video id). While it loads — or for items
//  with no video id, or if the image fails — the card falls back to a DESIGNED
//  tile: the team crest on a neutral gradient. The play badge / duration /
//  platform glyph overlay sits on top of whichever background is shown. When a
//  real content backend lands, only TeamContentProvider changes; this view does
//  not.
//

import SwiftUI

struct TeamContentCard: View {
    let item: TeamContentItem
    /// Resolved from the followed Club directory by abbreviation (crest + name for
    /// the attribution line). Optional so a missing match degrades gracefully.
    let club: Club?
    @Environment(\.openURL) private var openURL

    /// The team's accent color (legible on dark) — drives the 3px top accent line
    /// and the colored abbreviation in the source row.
    private var accentColor: Color { club?.accentColor ?? .dsAccent }

    var body: some View {
        Button {
            if let url = item.url { openURL(url) }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                // 3px team-color accent line along the top edge (design motif),
                // then the thumbnail.
                ZStack(alignment: .top) {
                    thumbnail
                    Rectangle()
                        .fill(accentColor)
                        .frame(height: 3)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.caption)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.dsFgPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    sourceRow
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.dsBgCard)
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// "WAS · YouTube" — abbreviation in team color, platform secondary.
    private var sourceRow: some View {
        HStack(spacing: 6) {
            Text(item.teamAbbreviation)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accentColor)
            Text("·").foregroundStyle(Color.dsFgQuaternary)
            Text(item.platform.rawValue)
                .font(.system(size: 12))
                .foregroundStyle(Color.dsFgSecondary)
        }
    }

    // MARK: - Thumbnail (real YouTube frame, designed-tile fallback — see file note)

    private var thumbnail: some View {
        ZStack {
            thumbnailBackground
            thumbnailOverlay
        }
        .frame(height: 168)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    /// The real video frame when available, else the designed crest tile. The
    /// tile also covers the AsyncImage's loading and failure phases.
    @ViewBuilder
    private var thumbnailBackground: some View {
        if let thumbnailURL = item.thumbnailURL {
            AsyncImage(url: thumbnailURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    designedTile
                }
            }
        } else {
            designedTile
        }
    }

    /// Crest on a neutral gradient — the placeholder/fallback look.
    private var designedTile: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.systemGray5), Color(.systemGray4)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            TeamLogo(urlString: club?.logoURL, size: 56)
                .opacity(0.9)
        }
    }

    /// Centered play badge over the thumbnail (video items only). The platform +
    /// team now read from the source row below, so the thumbnail stays clean.
    @ViewBuilder
    private var thumbnailOverlay: some View {
        if item.platform.isVideo {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.9))
                .shadow(radius: 4)
        }
    }
}
