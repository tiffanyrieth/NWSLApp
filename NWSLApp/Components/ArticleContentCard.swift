//
//  ArticleContentCard.swift
//  NWSLApp
//
//  The news-article content card (Content Card Spec variant 5; Feed + Home club
//  news), facelift to `feed.jsx`: an identity row (author-initials avatar + name +
//  a green NEWS pill + outlet, with a right-column team pill + time), a bold
//  headline, a 2-line summary blurb, and — only when an image is on file — a
//  FULL-WIDTH 16:9 image, closed by a "Read on {outlet} →" link. An image-less
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

    /// The outlet name (for the NEWS line and the CTA).
    private var outlet: String { card.sourceName ?? card.authorName ?? "News" }
    /// The prominent identity: a byline author when known, else the outlet.
    private var primaryName: String { card.authorName ?? outlet }
    /// Show the outlet on the NEWS line only when the author is the primary name
    /// (otherwise it'd just repeat the outlet).
    private var secondaryOutlet: String? { card.authorName != nil ? card.sourceName : nil }

    var body: some View {
        // `.onTapGesture`, not a `Button` — see ThumbnailContentCard for why (a chip
        // tap on Home could otherwise be re-delivered to the first card's Button; #3).
        VStack(alignment: .leading, spacing: 11) {
            headerRow
            if let headline = card.headline {
                Text(headline)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.dsFgPrimary)
                    .lineSpacing(2)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let blurb = card.blurb, !blurb.isEmpty {
                Text(blurb)
                    .font(.system(size: 13))
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

    // MARK: - Header (avatar + name / NEWS · outlet + team pill / time)

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 11) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(primaryName)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Color.dsFgPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    newsPill
                    if let secondaryOutlet {
                        Text(secondaryOutlet)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.dsFgSecondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                if !hideTeamIdentity, let abbr = card.teamAbbreviation {
                    teamPill(abbr)
                }
                Text(card.timestamp.relativeAgo)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.dsFgTertiary)
            }
        }
    }

    private var avatar: some View {
        ZStack {
            Circle().fill(teamColor.opacity(0.15))
            Text(initials)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(teamColor)
        }
        .frame(width: DS.contentAvatar, height: DS.contentAvatar)
    }

    private var initials: String {
        let parts = primaryName.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init)
        return letters.isEmpty ? "•" : letters.joined().uppercased()
    }

    private var newsPill: some View {
        Text("NEWS")
            .font(.system(size: 9.5, weight: .bold))
            .tracking(0.4)
            .foregroundStyle(Color.dsStateFinal)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Color.dsStateFinal.opacity(0.16), in: Capsule())
    }

    private func teamPill(_ abbr: String) -> some View {
        Text(abbr)
            .font(.system(size: 10.5, weight: .bold))
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
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusMd, style: .continuous))
    }

    // MARK: - CTA

    private var readOnOutlet: some View {
        HStack(spacing: 4) {
            Text("Read on \(outlet)")
                .font(.system(size: 13, weight: .semibold))
            Image(systemName: "arrow.right")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(Color.dsAccent)
    }
}
