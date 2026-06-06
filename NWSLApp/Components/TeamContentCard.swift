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

    var body: some View {
        Button {
            if let url = item.url { openURL(url) }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                thumbnail
                VStack(alignment: .leading, spacing: 8) {
                    attribution
                    Text(item.caption)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    sourceTag
                }
                .padding(14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
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

    /// Play badge (center) + platform glyph (top-left) + duration (bottom-right),
    /// drawn over whichever background is shown.
    private var thumbnailOverlay: some View {
        ZStack {
            if item.platform.isVideo {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(radius: 4)
            }
            VStack {
                HStack {
                    platformGlyph
                    Spacer()
                }
                Spacer()
                HStack {
                    Spacer()
                    if let duration = item.durationLabel {
                        Text(duration)
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 5))
                    }
                }
            }
            .padding(8)
        }
    }

    private var platformGlyph: some View {
        Image(systemName: item.platform.symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(6)
            .background(.black.opacity(0.55), in: Circle())
    }

    // MARK: - Attribution + source tag

    private var attribution: some View {
        HStack(spacing: 8) {
            TeamLogo(urlString: club?.logoURL, size: 20)
            Text(teamName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text("· \(relativeTimestamp)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private var sourceTag: some View {
        Text(item.sourceTag)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
    }

    private var teamName: String {
        club?.shortName ?? club?.displayName ?? item.teamAbbreviation
    }

    private var relativeTimestamp: String {
        Self.relativeFormatter.localizedString(for: item.timestamp, relativeTo: Date())
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated   // "2h ago"
        return f
    }()
}
