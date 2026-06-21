//
//  ArticleContentCard.swift
//  NWSLApp
//
//  The news-article content card (Content Card Spec variant 5; Social Headlines +
//  Home club news), unified with the social cards per `Feed.html`: ONE meta row —
//  club-code pill + a green NEWS category pill + plain muted outlet + time (no
//  source-initials avatar) — then a bold headline, a 2-line summary blurb, and —
//  only when an image is on file — a FULL-WIDTH 16:9 image, closed by a "Read on
//  {outlet} →" link. This is the only card kept in article format; reporters/league
//  render as Bluesky social posts. An image-less
//  article still reads as deliberate (left team bar + identity + headline + blurb +
//  link carry it — no empty placeholder block). Per the Feed's legal note we only
//  ever show the headline + blurb + link, never the article body.
//

import SwiftUI

struct ArticleContentCard: View {
    let card: ContentCard
    var club: Club?
    /// Following one team → drop the right-column team pill (redundant on Home).
    var hideTeamIdentity: Bool = false
    @Environment(\.openURL) private var openURL

    private var teamColor: Color { club?.accentColor ?? .dsAccent }

    /// The outlet name (the muted source text + the "Read on …" CTA).
    private var outlet: String { card.sourceName ?? card.authorName ?? "News" }

    var body: some View {
        // `.onTapGesture`, not a `Button` — see ThumbnailContentCard for why (a chip
        // tap on Home could otherwise be re-delivered to the first card's Button; #3).
        VStack(alignment: .leading, spacing: 11) {
            headerRow
            if let headline = card.headline {
                Text(headline)
                    .dsFont(16, weight: .bold)
                    .foregroundStyle(Color.dsFgPrimary)
                    .lineSpacing(2)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let blurb = card.blurb, !blurb.isEmpty {
                Text(blurb)
                    .dsFont(13)
                    .foregroundStyle(Color.dsFgSecondary)
                    .lineSpacing(3)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Full-width 16:9 ONLY when an image is on file — no placeholder block
            // when absent (the card reads fine without it).
            if card.thumbnailURL != nil { articleImage }
            readOnOutlet
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsBgCard)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = card.url { openURL(url) }
        }
    }

    // MARK: - Header (one meta row: club code · NEWS pill · outlet … time)

    // Matches the social cards (Feed.html): no source-initials avatar, the NEWS
    // category pill replaces the old hand-rolled one, outlet is plain muted text.
    /// Whether the article renders its image (so the team code rides on it, not inline).
    private var hasImage: Bool { card.thumbnailURL != nil }

    private var headerRow: some View {
        HStack(spacing: 7) {
            // Inline team code ONLY when there's no image; otherwise it sits bottom-left
            // on the article image (see `articleImage`). Gated on 2+ clubs.
            if !hideTeamIdentity, !hasImage, let abbr = card.teamAbbreviation {
                teamPill(abbr)
            }
            CategoryPill(sourceType: card.resolvedSourceType)
            Text(outlet)
                .dsFont(12)
                .foregroundStyle(Color.dsFgSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            Text(card.timestamp.relativeAgo)
                .dsFont(11)
                .foregroundStyle(Color.dsFgSecondary)
                .layoutPriority(1)
        }
    }

    private func teamPill(_ abbr: String) -> some View {
        Text(abbr)
            .dsFont(10.5, weight: .bold)
            .tracking(0.3)
            .foregroundStyle(teamColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(teamColor.opacity(0.13), in: Capsule())
    }

    // MARK: - Full-width article image (16:9, matches the card's inner radius)

    private var articleImage: some View {
        Color.clear
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay {
                ZStack {
                    LinearGradient(colors: [teamColor.opacity(0.18), Color.dsBgTertiary],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    // Cached so the frame survives a tab switch; a miss/404 → the gradient.
                    CachedThumbnail(url: card.thumbnailURL) { Color.clear }
                }
            }
            // The single team label, bottom-left on the image (gated on 2+ clubs).
            .overlay(alignment: .bottomLeading) {
                if !hideTeamIdentity, let abbr = card.teamAbbreviation {
                    MediaTeamBadge(club: club, abbreviation: abbr).padding(8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusMd, style: .continuous))
    }

    // MARK: - CTA

    private var readOnOutlet: some View {
        HStack(spacing: 4) {
            Text("Read on \(outlet)")
                .dsFont(13, weight: .semibold)
            Image(systemName: "arrow.right")
                .dsFont(11, weight: .semibold)
        }
        .foregroundStyle(Color.dsAccent)
    }
}
