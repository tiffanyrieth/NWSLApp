//
//  ArticleContentCard.swift
//  NWSLApp
//
//  The news-article content card (Content Card Spec variant 5): club news on Home,
//  Headlines on Social. The header is ONE meta row — a NEWS badge (Home: a plain NEWS
//  pill; Social: the source-class CategoryPill) on the left + the timestamp on the right.
//  No source/club name line: it's redundant with the badge, the left team-color bar, the
//  abbreviation pill, and the "Read on {outlet} →" link. Then a bold headline, a 2-line
//  summary blurb, and — only when an image is on file — a FULL-WIDTH 16:9 image, closed by
//  the "Read on {outlet} →" link. The ONE team label is the abbreviation-only chip pinned
//  BOTTOM-LEFT — on the image when present, else on the CTA row — gated on 2+ clubs. Per
//  the Feed's legal note we only ever show headline + blurb + link, never the article body.
//

import SwiftUI

struct ArticleContentCard: View {
    let card: ContentCard
    var club: Club?
    /// Following one team → drop the team label (redundant on Home).
    var hideTeamIdentity: Bool = false
    /// Social tab: the unified meta row (no avatar). Home keeps its original identity row.
    var unified: Bool = false
    @Environment(\.openURL) private var openURL

    private var teamColor: Color { club?.accentColor ?? .dsAccent }

    /// The outlet name — used only by the "Read on …" CTA now (the header no longer shows
    /// a source/club name; the NEWS badge + team color bar + this CTA carry the source).
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
            footerRow
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

    // MARK: - Header (per-tab)

    /// Whether the article renders its image (so the team code rides on it, not inline).
    private var hasImage: Bool { card.thumbnailURL != nil }

    @ViewBuilder
    private var headerRow: some View {
        if unified { unifiedHeader } else { legacyHeader }
    }

    /// Social: one meta row — source-class CategoryPill + timestamp, no source/club name.
    /// Inline team code only when there's no image to host it (see `articleImage`).
    private var unifiedHeader: some View {
        HStack(spacing: 7) {
            if !hideTeamIdentity, !hasImage, let abbr = card.teamAbbreviation {
                teamPill(abbr)
            }
            CategoryPill(sourceType: card.resolvedSourceType)
            Spacer(minLength: 6)
            Text(card.timestamp.relativeAgo)
                .dsFont(11)
                .foregroundStyle(Color.dsFgSecondary)
                .layoutPriority(1)
        }
    }

    /// Home: one meta row — the green NEWS pill + timestamp, no source/club name (the team
    /// is already carried by the color bar + abbr chip + "Read on …" link). The team code
    /// rides bottom-left: on the media when there's an image, else on the CTA footer row.
    private var legacyHeader: some View {
        HStack(spacing: 8) {
            newsPill
            Spacer(minLength: 8)
            Text(card.timestamp.relativeAgo)
                .dsFont(11)
                .foregroundStyle(Color.dsFgSecondary)
        }
    }

    private var newsPill: some View {
        Text("NEWS")
            .dsFont(9.5, weight: .bold)
            .tracking(0.4)
            .foregroundStyle(Color.dsStateFinal)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Color.dsStateFinal.opacity(0.16), in: Capsule())
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

    // MARK: - Footer (CTA + bottom-left team chip when there's no image to host it)

    /// The "Read on …" CTA, with the team abbreviation chip pinned BOTTOM-LEFT when the card
    /// has no image to carry it (image cards keep the chip on the media — see `articleImage`).
    /// Home only: Social's `unifiedHeader` keeps its inline chip, so we'd double up otherwise.
    private var footerRow: some View {
        HStack(spacing: 10) {
            if !unified, !hideTeamIdentity, !hasImage, let abbr = card.teamAbbreviation {
                teamPill(abbr)
            }
            readOnOutlet
            Spacer(minLength: 0)
        }
    }

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
