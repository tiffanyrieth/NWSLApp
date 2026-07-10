//
//  ThumbnailContentCard.swift
//  NWSLApp
//
//  The thumbnail-forward content cards: a big image area with overlays on top,
//  then a footer. Covers the two Content Card Spec variants built this way:
//   • 1 youtube     — a team's YouTube video (Home); team stripe + crest badge +
//                     centered play + duration pill; footer = title + "YouTube · 2h".
//   • 6 socialVideo — a TikTok/Instagram clip surfaced via Reddit (Feed + Home);
//                     platform chip + centered play + optional team badge; footer =
//                     "@creator · via r/sub · 2h" + caption + "Open in TikTok ↗".
//
//  The thumbnail composition (background image-or-gradient + the overlay slots)
//  lives in `ThumbnailHeader` below, parameterized so each layout passes only the
//  slots it needs. Whole card opens `card.url`, like the other content cards.
//

import SwiftUI

struct ThumbnailContentCard: View {
    let card: ContentCard
    var club: Club?
    /// YouTube only: the compact 120pt thumbnail instead of the 180pt hero.
    var compact: Bool = false
    /// Following one team → drop the team label on the thumbnail (redundant).
    var hideTeamIdentity: Bool = false
    /// Social tab: show the source-class category pill in the footer. Home keeps its
    /// original footer (no category pill) — this is the only per-tab card difference.
    var unified: Bool = false
    @Environment(\.openURL) private var openURL

    /// Team accent for the stripe/badges/gradient. A creator clip with no team
    /// falls back to a neutral dark so the gradient stays subtle (spec's "#333").
    private var teamColor: Color {
        if let club { return club.accentColor }
        return card.layout == .socialVideo ? Color(hex: "#444444") : .dsAccent
    }

    var body: some View {
        // Whole-card tap via `.onTapGesture`, NOT a `Button`: on Home the chip filter
        // bar and these cards share one scroll, and a chip Button's tap could be
        // re-delivered to the first card *Button* on the filter-change rebuild —
        // flashing it pressed and opening its URL (bug #3). With no card Button there's
        // nothing to mis-fire. (Feed avoids it by isolating its chips in a separate
        // scroll; Home can't, so it fixes it here.)
        VStack(alignment: .leading, spacing: 0) {
            thumbnail
            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsBgCard)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = card.url { openURL(url) }
        }
    }

    // MARK: - Thumbnail (per layout)

    @ViewBuilder
    private var thumbnail: some View {
        switch card.layout {
        case .socialVideo:
            ThumbnailHeader(
                thumbnailURL: card.thumbnailURL, height: 200, teamColor: teamColor, club: club,
                // No top stripe — the facelift's left-edge team bar (ContentCardView)
                // now carries team color down the whole card.
                playSize: 52,
                crestBadge: hideTeamIdentity ? nil : card.teamAbbreviation.map {
                    ThumbnailHeader.BadgeSlot(abbreviation: $0, alignment: .bottomLeading)
                },
                platformChip: ThumbnailHeader.ChipSlot(
                    platform: card.platform, label: platformLabel, alignment: .topTrailing
                )
            )
        default:   // .youtube
            ThumbnailHeader(
                thumbnailURL: card.thumbnailURL, height: compact ? 120 : 180,
                teamColor: teamColor, club: club,
                playSize: compact ? 40 : 52, duration: card.duration,
                crestBadge: hideTeamIdentity ? nil : card.teamAbbreviation.map {
                    ThumbnailHeader.BadgeSlot(abbreviation: $0, alignment: .bottomLeading)
                }
            )
        }
    }

    private var platformLabel: String {
        card.platform == .instagram ? "Instagram" : "TikTok"
    }

    // MARK: - Footer (per layout)

    @ViewBuilder
    private var footer: some View {
        switch card.layout {
        case .socialVideo: socialFooter
        default:           youtubeFooter
        }
    }

    private var youtubeFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title = card.title {
                Text(title)
                    .dsFont(15, weight: .semibold)
                    .foregroundStyle(Color.dsFgPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                if unified { CategoryPill(sourceType: card.resolvedSourceType) }   // CLUB (Social only)
                PlatformBadge(platform: .youtube, size: 14)
                Text("YouTube")
                Text("·")
                Text(card.timestamp.relativeAgo)
            }
            .dsFont(12)
            .foregroundStyle(Color.dsFgSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }

    private var socialFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if unified { CategoryPill(sourceType: card.resolvedSourceType) }   // PLAYER (Social only)
                // The author + "via r/sub" attribution is the creator's identity — kept.
                // A club's own clip would just repeat the club name (redundant with the
                // pill + color bar + team chip), so for `.club` we show only the timestamp.
                if card.resolvedSourceType != .club {
                    if let author = card.authorName, !author.isEmpty {
                        Text(author)
                            .dsFont(14, weight: .bold)
                            .foregroundStyle(Color.dsFgPrimary)
                            .lineLimit(1)
                    }
                    if let sub = card.subreddit {
                        Text("via")
                            .dsFont(12)
                            .foregroundStyle(Color.dsFgSecondary)
                        PlatformBadge(platform: .reddit, size: 13)
                        Text("r/\(sub)")
                            .dsFont(12, weight: .semibold)
                            .foregroundStyle(Color(hex: "#FF4500"))
                            .lineLimit(1)
                    }
                    Text("· \(card.timestamp.relativeAgo)")
                        .dsFont(12)
                        .foregroundStyle(Color.dsFgSecondary)
                        .lineLimit(1)
                } else {
                    Text(card.timestamp.relativeAgo)
                        .dsFont(12)
                        .foregroundStyle(Color.dsFgSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            if let caption = card.bodyText ?? card.title {
                Text(caption)
                    .dsFont(14)
                    .foregroundStyle(Color.dsFgSecondary)
                    .lineSpacing(3)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            CTARow(label: card.ctaLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }
}

// MARK: - Thumbnail header (background + overlay slots)

/// The image area shared by the thumbnail-forward cards. Renders a background
/// (the real frame when present, else a team-tinted gradient with a crest
/// fallback — never a broken image) plus whichever overlay slots the caller
/// passes: a top team stripe, a centered play button, a duration pill, a team
/// crest badge, and/or a platform chip.
struct ThumbnailHeader: View {
    let thumbnailURL: URL?
    let height: CGFloat
    let teamColor: Color
    var club: Club? = nil
    var topStripe: Bool = false
    var playSize: CGFloat? = nil
    var duration: String? = nil
    var crestBadge: BadgeSlot? = nil
    var platformChip: ChipSlot? = nil

    struct BadgeSlot { let abbreviation: String; let alignment: Alignment }
    struct ChipSlot { let platform: ContentCard.Platform; let label: String; let alignment: Alignment }

    var body: some View {
        background
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipped()
            .overlay { overlays }
    }

    // MARK: Background

    private var background: some View {
        ZStack {
            LinearGradient(colors: [teamColor.opacity(0.15), Color.dsBgTertiary],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            // Cached so a tab-switch return doesn't flash back to the crest while the
            // frame reloads (bug #5). Miss/failure → crest over the gradient.
            CachedThumbnail(url: thumbnailURL) { crestFallback }
        }
    }

    @ViewBuilder
    private var crestFallback: some View {
        if let logo = club?.logoURL {
            TeamLogo(urlString: logo, teamAbbreviation: club?.abbreviation, size: 56).opacity(0.9)
        }
    }

    // MARK: Overlays

    private var overlays: some View {
        ZStack {
            if topStripe {
                Rectangle().fill(teamColor)
                    .frame(height: 3)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            if let playSize {
                playButton(playSize)
            }
            if let crestBadge {
                MediaTeamBadge(club: club, abbreviation: crestBadge.abbreviation)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: crestBadge.alignment)
                    .padding(10)
            }
            if let platformChip {
                platformChipPill(platformChip)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: platformChip.alignment)
                    .padding(10)
            }
            if let duration {
                durationPill(duration)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(8)
            }
        }
    }

    private func playButton(_ size: CGFloat) -> some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.7))
            Circle().stroke(Color.white.opacity(0.25), lineWidth: 2)
            Image(systemName: "play.fill")
                .dsFont(size >= 52 ? 18 : 14)
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }

    private func platformChipPill(_ chip: ChipSlot) -> some View {
        HStack(spacing: 5) {
            PlatformBadge(platform: chip.platform, size: 14)
            Text(chip.label)
                .dsFont(11, weight: .semibold)
                .foregroundStyle(.white)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.black.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func durationPill(_ text: String) -> some View {
        Text(text)
            .dsFont(11, weight: .semibold, monospacedDigit: true)
            .foregroundStyle(.white)
            .padding(.vertical, 2)
            .padding(.horizontal, 6)
            .background(Color.black.opacity(0.75))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

// MARK: - Media team badge

/// The single bottom-left "which club" label overlaid on a content card's media: just
/// the team ABBREVIATION in team color on a subtle translucent-dark chip — no crest
/// (the abbreviation alone identifies the club; the crest was visual noise). Shared by
/// all card layouts' media so Home + Social read identically; gated by the caller on 2+
/// followed clubs.
struct MediaTeamBadge: View {
    var club: Club?
    let abbreviation: String

    private var teamColor: Color { club?.accentColor ?? .white }

    var body: some View {
        Text(abbreviation)
            .dsFont(11, weight: .semibold)
            .foregroundStyle(teamColor)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(Color.black.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
