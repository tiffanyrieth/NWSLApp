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
//  TEMP (no media backend): the thumbnail is a DESIGNED placeholder — the team
//  crest on a neutral gradient with a play badge / duration / platform glyph — not
//  a fetched image. The seed (TeamContentProvider) uses durable account-level URLs
//  that expose no per-post image; when a real content source lands, swap in a real
//  thumbnail URL here (an AsyncImage over `item.thumbnailURL`) and the rest of the
//  card is unchanged.
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

    // MARK: - Thumbnail (designed placeholder — see file note)

    private var thumbnail: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.systemGray5), Color(.systemGray4)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            TeamLogo(urlString: club?.logoURL, size: 56)
                .opacity(0.9)
            if item.platform.isVideo {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(radius: 4)
            }
            // Platform glyph (top-left) + duration (bottom-right).
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
        .frame(height: 168)
        .frame(maxWidth: .infinity)
        .clipped()
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
