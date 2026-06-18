//
//  AvatarContentCard.swift
//  NWSLApp
//
//  The avatar-led content cards (Feed social + Home club-social), facelift to
//  `feed.jsx`: an author-initials avatar in the team tint, a TWO-LINE identity
//  (name + platform badge / a platform-color dot + "handle · Platform"), and a
//  right column (team-abbr pill + time). Below the header — full width — the post
//  body, optional media, and the like/repost + CTA row. Covers four of the seven
//  Content Card Spec variants that share this anatomy:
//   • 2 blueskyTeamText  — team post, text only
//   • 3 blueskyTeamMedia — team post with a media thumbnail
//   • 4 blueskyReporter  — reporter post (Feed)
//   • 7 instagramFallback — IG post with no thumbnail → a "view on Instagram" strip
//
//  The whole card is the tap target, opening `card.url`. The 3px team-color left
//  edge is added by ContentCardView (shared across every content-card layout).
//
//  This file also defines the small subviews shared across the content-card files —
//  EngagementRow and CTARow — kept here as the card "atoms".
//

import SwiftUI

struct AvatarContentCard: View {
    let card: ContentCard
    var club: Club?
    /// Following one team → drop the right-column team pill (redundant on Home).
    var hideTeamIdentity: Bool = false
    @Environment(\.openURL) private var openURL

    private var teamColor: Color { club?.accentColor ?? .dsAccent }

    var body: some View {
        // `.onTapGesture`, not a `Button` — see ThumbnailContentCard for why (a chip
        // tap on Home could otherwise be re-delivered to the first card's Button; #3).
        VStack(alignment: .leading, spacing: 11) {
            headerRow
            postBody
            media
            bottomRow
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

    // MARK: - Header (avatar + two-line identity + team pill / time)

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 11) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(displayName)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Color.dsFgPrimary)
                        .lineLimit(1)
                    PlatformBadge(platform: card.platform, size: 14)
                }
                HStack(spacing: 6) {
                    Circle().fill(platformColor).frame(width: 6, height: 6)
                    Text(handleLine)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.dsFgSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                if !hideTeamIdentity, let abbr = card.teamAbbreviation {
                    teamPill(abbr)
                }
                Text(card.timestamp.relativeAgo)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.dsFgSecondary)
            }
        }
    }

    /// The poster: a reporter/author name, else the club, else the abbreviation.
    private var displayName: String {
        card.authorName ?? club?.displayName ?? card.teamAbbreviation ?? "—"
    }

    /// "@handle · Bluesky" when a handle is known, else just the platform name.
    private var handleLine: String {
        if let handle = card.handle, !handle.isEmpty {
            return "\(handle) · \(platformName)"
        }
        return platformName
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
        let parts = displayName.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init)
        return letters.isEmpty ? "•" : letters.joined().uppercased()
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

    /// The platform's brand color, for the meta-line dot (mirrors PlatformBadge).
    private var platformColor: Color {
        switch card.platform {
        case .youtube:   return Color(hex: "#FF0000")
        case .bluesky:   return Color(hex: "#0085FF")
        case .tiktok:    return Color(hex: "#000000")
        case .instagram: return Color(hex: "#DD2A7B")
        case .article:   return Color(hex: "#636366")
        case .reddit:    return Color(hex: "#FF4500")
        }
    }

    private var platformName: String {
        switch card.platform {
        case .youtube:   return "YouTube"
        case .bluesky:   return "Bluesky"
        case .tiktok:    return "TikTok"
        case .instagram: return "Instagram"
        case .article:   return "Article"
        case .reddit:    return "Reddit"
        }
    }

    // MARK: - Body (full width, below the header)

    @ViewBuilder
    private var postBody: some View {
        if let text = card.bodyText, !text.isEmpty {
            Text(text)
                .font(.system(size: 14.5))
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
        .foregroundStyle(Color.dsFgSecondary)
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
