//
//  AvatarContentCard.swift
//  NWSLApp
//
//  The avatar-led content cards: an avatar on the left, then a column of
//  header / body / optional media / engagement+CTA. Covers four of the seven
//  Content Card Spec variants that share this anatomy:
//   • 2 blueskyTeamText  — team post, text only, team-ring avatar
//   • 3 blueskyTeamMedia — team post with a media thumbnail
//   • 4 blueskyReporter  — reporter post, solid-accent initial avatar (Feed)
//   • 7 instagramFallback — IG post with no thumbnail → a "view on Instagram" strip
//
//  Per-layout differences (clamp counts, which avatar, whether there's media or an
//  engagement row) are switched here off `card.layout`. The whole card is the tap
//  target, opening `card.url`, matching the other content cards.
//
//  This file also defines the small subviews shared across all three content-card
//  files — TeamRingAvatar, EngagementRow, CTARow — kept together as the card
//  "atoms" rather than scattered, since they're meaningless outside this feature.
//

import SwiftUI

struct AvatarContentCard: View {
    let card: ContentCard
    var club: Club?
    /// Following one team → drop the team name from the header (just platform + time).
    var hideTeamIdentity: Bool = false
    @Environment(\.openURL) private var openURL

    private var teamColor: Color { club?.accentColor ?? .dsAccent }

    var body: some View {
        // `.onTapGesture`, not a `Button` — see ThumbnailContentCard for why (a chip
        // tap on Home could otherwise be re-delivered to the first card's Button; #3).
        VStack(spacing: 0) {
            // No top stripe — team color now reads as the facelift's left-edge bar
            // (ContentCardView), shared by every content-card layout.
            HStack(alignment: .top, spacing: 10) {
                avatar
                VStack(alignment: .leading, spacing: columnGap) {
                    header
                    postBody
                    media
                    bottomRow
                }
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsBgCard)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = card.url { openURL(url) }
        }
    }

    private var columnGap: CGFloat { card.layout == .blueskyTeamText ? 8 : 10 }

    // MARK: - Avatar

    @ViewBuilder
    private var avatar: some View {
        switch card.layout {
        case .blueskyReporter:
            // Reporter: a solid-accent disc with the first initial (not team-tinted)
            // — the Feed's own voice, distinct from team posts.
            TeamRingAvatar(style: .solidAccentInitial, teamColor: teamColor,
                           text: initial(of: card.authorName))
        case .instagramFallback:
            TeamRingAvatar(style: .teamRingFilled, teamColor: teamColor,
                           text: card.teamAbbreviation ?? "")
        default:
            TeamRingAvatar(style: .teamRing, teamColor: teamColor,
                           text: card.teamAbbreviation ?? "")
        }
    }

    private func initial(of name: String?) -> String {
        guard let first = name?.first else { return "•" }
        return String(first).uppercased()
    }

    // MARK: - Header (name + platform badge + handle · time)

    private var header: some View {
        HStack(spacing: 6) {
            // Team name is dropped when following one team (redundant); the platform
            // badge + timestamp stay so the card still reads as "<platform> · 2d ago".
            if !hideTeamIdentity {
                Text(card.authorName ?? club?.displayName ?? "")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.dsFgPrimary)
                    .lineLimit(1)
            }
            PlatformBadge(platform: card.platform, size: 14)
            Text(hideTeamIdentity ? card.timestamp.relativeAgo : metaLine)
                .font(.system(size: 12))
                .foregroundStyle(Color.dsFgTertiary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private var metaLine: String {
        if let handle = card.handle, !handle.isEmpty {
            return "\(handle) · \(card.timestamp.relativeAgo)"
        }
        return card.timestamp.relativeAgo
    }

    // MARK: - Body

    @ViewBuilder
    private var postBody: some View {
        if let text = card.bodyText, !text.isEmpty {
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Color.dsFgPrimary)
                .lineSpacing(3)
                .lineLimit(bodyClamp)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var bodyClamp: Int {
        switch card.layout {
        case .blueskyTeamText:   return 4
        case .blueskyTeamMedia:  return 2
        case .blueskyReporter:   return 5
        case .instagramFallback: return 3
        default:                 return 4
        }
    }

    // MARK: - Media (per layout)

    @ViewBuilder
    private var media: some View {
        switch card.layout {
        case .blueskyTeamMedia:
            mediaThumbnail(height: 160, gradientTop: teamColor.opacity(0.20))
        case .blueskyReporter:
            if card.thumbnailURL != nil {
                mediaThumbnail(height: 140, gradientTop: Color.dsAccent.opacity(0.10))
            }
        case .instagramFallback:
            instagramStrip
        default:
            EmptyView()
        }
    }

    /// A full-width media tile: the real frame when present, else a team/accent
    /// gradient (never a broken image).
    private func mediaThumbnail(height: CGFloat, gradientTop: Color) -> some View {
        ZStack {
            LinearGradient(colors: [gradientTop, Color.dsBgTertiary],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            // Cached so the frame survives a tab switch (bug #5); miss → the gradient.
            CachedThumbnail(url: card.thumbnailURL) { Color.clear }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusMd, style: .continuous))
    }

    /// Layout 7's no-thumbnail fallback: a tappable "view on Instagram" strip in
    /// the team's tint, so an IG post still reads as a deliberate card.
    private var instagramStrip: some View {
        HStack(spacing: 8) {
            PlatformBadge(platform: .instagram, size: 20)
            Text("View full post on Instagram")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.dsFgSecondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .background(
            LinearGradient(colors: [teamColor.opacity(0.15), teamColor.opacity(0.08)],
                           startPoint: .leading, endPoint: .trailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusMd, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusMd, style: .continuous)
                .stroke(teamColor.opacity(0.20), lineWidth: 1)
        )
    }

    // MARK: - Bottom row (engagement + CTA, or just CTA for IG fallback)

    @ViewBuilder
    private var bottomRow: some View {
        if card.layout == .instagramFallback {
            HStack {
                CTARow(label: card.ctaLabel)
                Spacer(minLength: 0)
            }
        } else {
            EngagementRow(likes: card.likes, reposts: card.reposts, ctaLabel: card.ctaLabel)
        }
    }
}

// MARK: - Shared card atoms

/// The circular avatar on the avatar-led cards, in three styles: a team-color
/// ring (team posts), the same ring on a faint team fill (IG fallback), or a
/// solid-accent disc with an initial (reporters — the Feed's own voice).
struct TeamRingAvatar: View {
    enum Style { case teamRing, teamRingFilled, solidAccentInitial }

    let style: Style
    let teamColor: Color
    let text: String
    var size: CGFloat = DS.contentAvatar

    var body: some View {
        ZStack {
            Circle().fill(backgroundFill)
            Text(text)
                .font(.system(size: textSize, weight: .bold))
                .foregroundStyle(textColor)
        }
        .frame(width: size, height: size)
        .overlay {
            if style != .solidAccentInitial {
                Circle().stroke(teamColor, lineWidth: 2)
            }
        }
    }

    private var backgroundFill: Color {
        switch style {
        case .teamRing:           return Color.black.opacity(0.4)
        case .teamRingFilled:     return teamColor.opacity(0.2)
        case .solidAccentInitial: return Color.dsAccent
        }
    }

    private var textColor: Color {
        style == .solidAccentInitial ? .white : teamColor
    }

    private var textSize: CGFloat {
        style == .solidAccentInitial ? 15 : 11
    }
}

/// The like/repost counts with the action link trailing — the bottom row of the
/// Bluesky cards. Counts are hidden when nil so a card without engagement data
/// still shows a clean CTA on the right.
struct EngagementRow: View {
    let likes: Int?
    let reposts: Int?
    let ctaLabel: String

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 16) {
                if let likes { metric("heart", likes) }
                if let reposts { metric("arrow.2.squarepath", reposts) }
            }
            Spacer(minLength: 8)
            CTARow(label: ctaLabel)
        }
    }

    private func metric(_ symbol: String, _ count: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text("\(count)")
        }
        .font(.system(size: 12))
        .foregroundStyle(Color.dsFgTertiary)
    }
}

/// The accent "Read article ↗" / "View on Bluesky ↗" action link shared by every
/// content card.
struct CTARow: View {
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
            Image(systemName: "arrow.up.right")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(Color.dsAccent)
    }
}
