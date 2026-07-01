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
                // Home (ADDENDUM v2): tighter 15pt headline clamped to 2 lines for density.
                // Social (unified) keeps the roomier 16pt / 3-line treatment.
                Text(headline)
                    .dsFont(unified ? 16 : 15, weight: .bold)
                    .foregroundStyle(Color.dsFgPrimary)
                    .lineSpacing(2)
                    .lineLimit(unified ? 3 : 2)
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
        // Home (ADDENDUM v2): tighter vertical padding (10/12) for density; Social keeps 14.
        .padding(.horizontal, 14)
        .padding(.top, unified ? 14 : 10)
        .padding(.bottom, unified ? 14 : 12)
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
    /// The team code rides bottom-left exactly like Home (on the media, else on the CTA
    /// footer row) so a card reads identically on both tabs — never inline here.
    private var unifiedHeader: some View {
        HStack(spacing: 7) {
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
        mediaContainer
            // The single team label, bottom-left on the image (gated on 2+ clubs).
            .overlay(alignment: .bottomLeading) {
                if !hideTeamIdentity, let abbr = card.teamAbbreviation {
                    MediaTeamBadge(club: club, abbreviation: abbr).padding(8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusMd, style: .continuous))
    }

    /// Home (ADDENDUM v2): a fixed 152pt media block, aspect-fill with a TOP-center crop
    /// (faces/action sit upper-center in sports photos) — shorter than the old 16:9 box so
    /// ~2.5 cards fit. Social (unified) keeps the full-width 16:9 letterbox-fit.
    @ViewBuilder
    private var mediaContainer: some View {
        if unified {
            Color.clear
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay { mediaFill }
        } else {
            Color.clear
                .frame(height: 152)
                .overlay { mediaFill }
                .clipped()
        }
    }

    /// The team-tinted gradient with the cached frame on top. `.top` alignment so the
    /// aspect-fill overflow is cropped from the bottom (top-center gravity). A miss/404 →
    /// the gradient shows through.
    private var mediaFill: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [teamColor.opacity(0.18), Color.dsBgTertiary],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            CachedThumbnail(url: card.thumbnailURL) { Color.clear }
        }
    }

    // MARK: - Footer (CTA + bottom-left team chip when there's no image to host it)

    /// The "Read on …" CTA, with the team abbreviation chip pinned BOTTOM-LEFT when the card
    /// has no image to carry it (image cards keep the chip on the media — see `articleImage`).
    /// Both tabs: the chip placement is identical on Home and Social (gated on 2+ clubs).
    private var footerRow: some View {
        HStack(spacing: 10) {
            if !hideTeamIdentity, !hasImage, let abbr = card.teamAbbreviation {
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
