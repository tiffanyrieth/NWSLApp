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
    @Environment(\.openURL) private var openURL

    /// Team accent for the stripe/badges/gradient. A creator clip with no team
    /// falls back to a neutral dark so the gradient stays subtle (spec's "#333").
    private var teamColor: Color {
        if let club { return club.accentColor }
        return card.layout == .socialVideo ? Color(hex: "#444444") : .dsAccent
    }

    var body: some View {
        Button {
            if let url = card.url { openURL(url) }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                thumbnail
                footer
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.dsBgCard)
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Thumbnail (per layout)

    @ViewBuilder
    private var thumbnail: some View {
        switch card.layout {
        case .socialVideo:
            ThumbnailHeader(
                thumbnailURL: card.thumbnailURL, height: 200, teamColor: teamColor, club: club,
                playSize: 52,
                crestBadge: card.teamAbbreviation.map {
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
                topStripe: true, playSize: compact ? 40 : 52, duration: card.duration,
                crestBadge: card.teamAbbreviation.map {
                    ThumbnailHeader.BadgeSlot(abbreviation: $0, alignment: .topLeading)
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
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.dsFgPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                PlatformBadge(platform: .youtube, size: 14)
                Text("YouTube")
                Text("·")
                Text(card.timestamp.relativeAgo)
            }
            .font(.system(size: 12))
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
                Text(card.authorName ?? "")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.dsFgPrimary)
                    .lineLimit(1)
                if let sub = card.subreddit {
                    Text("via")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.dsFgTertiary)
                    PlatformBadge(platform: .reddit, size: 13)
                    Text("r/\(sub)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: "#FF4500"))
                        .lineLimit(1)
                }
                Text("· \(card.timestamp.relativeAgo)")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.dsFgTertiary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            if let caption = card.bodyText ?? card.title {
                Text(caption)
                    .font(.system(size: 14))
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
            if let thumbnailURL {
                AsyncImage(url: thumbnailURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        crestFallback   // loading / failure → crest over the gradient
                    }
                }
            } else {
                crestFallback
            }
        }
    }

    @ViewBuilder
    private var crestFallback: some View {
        if let logo = club?.logoURL {
            TeamLogo(urlString: logo, size: 56).opacity(0.9)
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
                crestBadgePill(crestBadge.abbreviation)
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
                .font(.system(size: size >= 52 ? 18 : 14))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }

    private func crestBadgePill(_ abbreviation: String) -> some View {
        HStack(spacing: 5) {
            ZStack {
                Circle().stroke(teamColor, lineWidth: 1.5)
                Text(abbreviation)
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(teamColor)
            }
            .frame(width: 16, height: 16)
            Text(abbreviation)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(teamColor)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.black.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func platformChipPill(_ chip: ChipSlot) -> some View {
        HStack(spacing: 5) {
            PlatformBadge(platform: chip.platform, size: 14)
            Text(chip.label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.black.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func durationPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.vertical, 2)
            .padding(.horizontal, 6)
            .background(Color.black.opacity(0.75))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}
