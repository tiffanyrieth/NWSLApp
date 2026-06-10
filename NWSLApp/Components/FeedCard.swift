//
//  FeedCard.swift
//  NWSLApp
//
//  One Feed item as a card. A single component renders both content types (so
//  they read as one chronological stream), switching layout on `item.kind`:
//   • .reporterPost — @ avatar, reporter name, "Bluesky — 2h ago", full post
//     body, "View on Bluesky →".
//   • .articleLink  — newspaper avatar, publication, "Article — 4h ago", bold
//     headline + one-line summary, "Read on The Athletic →". Per the spec's
//     legal note we show headline + summary + link ONLY, never the article body.
//
//  The whole card is the tap target (opens the source); the link row is its
//  visible affordance. The card carries no per-team marker — the top filter bar
//  is the team selector, so an on-card team tag would be redundant.
//

import SwiftUI

struct FeedCard: View {
    let item: FeedItem
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let url = item.url { openURL(url) }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                header
                content
                linkRow
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.dsBgCard)
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Header (avatar + source + meta)

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(item.sourceName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.dsFgPrimary)
                    .lineLimit(1)
                Text(metaLine)
                    .font(.caption)
                    .foregroundStyle(Color.dsFgSecondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var avatar: some View {
        ZStack {
            Circle().fill(avatarColor)
            Text(avatarGlyph)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: DS.feedAvatar, height: DS.feedAvatar)
    }

    // MARK: - Content (body, or headline + summary)

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .reporterPost:
            if let body = item.body {
                Text(body)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.dsFgPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .articleLink:
            VStack(alignment: .leading, spacing: 4) {
                if let headline = item.headline {
                    Text(headline)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.dsFgPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let summary = item.summary {
                    Text(summary)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.dsFgSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Link row

    private var linkRow: some View {
        HStack(spacing: 4) {
            Text(item.linkLabel)
                .font(.system(size: 15, weight: .semibold))
            Image(systemName: "arrow.up.right")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(Color.dsAccent)
    }

    // MARK: - Per-kind styling

    private var avatarGlyph: String {
        switch item.kind {
        case .reporterPost: return "@"
        case .articleLink:  return "📰"
        }
    }

    private var avatarColor: Color {
        switch item.kind {
        case .reporterPost: return .dsAccent       // reporter post
        case .articleLink:  return .dsFgTertiary   // article
        }
    }

    private var metaLine: String {
        let relative = Self.relativeFormatter.localizedString(for: item.timestamp, relativeTo: Date())
        switch item.kind {
        case .reporterPost: return "\(item.platform) — \(relative)"
        case .articleLink:  return "Article — \(relative)"
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated   // "2h ago"
        return f
    }()
}

#Preview {
    ScrollView {
        VStack(spacing: 12) {
            FeedCard(item: FeedItem(
                id: "p", kind: .reporterPost,
                sourceName: "Meg Linehan", sourceHandle: "@meglinehan",
                platform: "Bluesky", timestamp: Date().addingTimeInterval(-7200),
                headline: nil, summary: nil,
                body: "Washington Spirit confirm they've exercised the contract option on their young attacker through 2027.",
                url: URL(string: "https://bsky.app"),
                teams: [FeedTeamTag(abbreviation: "WAS")],
                isLeague: false
            ))
            FeedCard(item: FeedItem(
                id: "a", kind: .articleLink,
                sourceName: "The Athletic", sourceHandle: nil,
                platform: "The Athletic", timestamp: Date().addingTimeInterval(-14400),
                headline: "NWSL power rankings: Where every team stands at the break",
                summary: "Kansas City stays top, but the Spirit are closing fast.",
                body: nil,
                url: URL(string: "https://theathletic.com"),
                teams: [],
                isLeague: true
            ))
        }
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}
