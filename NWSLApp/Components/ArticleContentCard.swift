//
//  ArticleContentCard.swift
//  NWSLApp
//
//  The news-article content card (Content Card Spec variant 5, Feed): a headline-
//  led layout — a small outlet favicon + name + time, a bold 3-line headline, an
//  optional 2-line blurb, and an optional 80×80 thumbnail on the right — closed by
//  a "Read article ↗" link. Per the Feed's legal note we only ever show the
//  headline + blurb + link, never the article body.
//

import SwiftUI

struct ArticleContentCard: View {
    let card: ContentCard
    var club: Club?
    @Environment(\.openURL) private var openURL

    private var sourceName: String { card.sourceName ?? card.authorName ?? "News" }

    /// Team accent for the top stripe — the same per-source color coding the
    /// thumbnail (video) cards use, so articles read as the same team's content.
    private var teamColor: Color { club?.accentColor ?? .dsAccent }

    /// The source mark: a club's own site shows that club's crest; anything else
    /// (e.g. a future Google-News outlet) falls back to the generic article badge.
    @ViewBuilder private var sourceIcon: some View {
        if let club {
            TeamLogo(urlString: club.logoURL, teamAbbreviation: club.abbreviation, size: 18)
        } else {
            PlatformBadge(platform: .article, size: 18)
        }
    }

    var body: some View {
        // `.onTapGesture`, not a `Button` — see ThumbnailContentCard for why (a chip
        // tap on Home could otherwise be re-delivered to the first card's Button; #3).
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                textColumn
                if card.thumbnailURL != nil { thumbnail }
            }
            CTARow(label: card.ctaLabel)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsBgCard)
        // Team-color top stripe — ONLY when the article is tagged to a team we
        // resolved a color for. League / international articles (The Equalizer, The
        // Guardian, untagged) have no team, so they get no stripe instead of a
        // meaningless blue fallback (bug: blue regardless of which team you follow).
        .overlay(alignment: .top) {
            if club != nil {
                Rectangle().fill(teamColor).frame(height: 3)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = card.url { openURL(url) }
        }
    }

    private var textColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            sourceRow
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sourceRow: some View {
        HStack(spacing: 6) {
            sourceIcon
            Text(sourceName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.dsFgSecondary)
                .lineLimit(1)
            Text("· \(card.timestamp.relativeAgo)")
                .font(.system(size: 12))
                .foregroundStyle(Color.dsFgTertiary)
                .lineLimit(1)
        }
    }

    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DS.radiusSm, style: .continuous)
                .fill(Color.dsBgTertiary)
            if let url = card.thumbnailURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.dsFgTertiary)
                    }
                }
            }
        }
        .frame(width: 80, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusSm, style: .continuous))
    }
}
