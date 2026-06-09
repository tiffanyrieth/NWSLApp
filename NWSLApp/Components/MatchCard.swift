//
//  MatchCard.swift
//  NWSLApp
//
//  One game as a self-contained card in ScheduleView (MLS-app style). Left:
//  stacked home/away rows, each a team crest + abbreviation, with scores once
//  the match is in progress or final. Right: status badge — kickoff time for
//  upcoming matches, "LIVE" + clock for in-progress, or the short status
//  detail ("FT") for finished matches.
//
//  Honors design rule #1: lives entirely inside its card, no overlays.
//  Clarity over density: a solid rounded card surface with breathing room so
//  ~4–5 games read cleanly per screen.
//

import SwiftUI

/// A non-NWSL competition tag for a match card (CONCACAF W, etc.): a colored
/// left accent + a pill at the top of the card.
///
/// TEMP / placeholder-ready (per the schedule design spec's "competition-aware
/// from day one" intent): MatchCard renders this fully, but nothing constructs a
/// non-nil value yet — every match we fetch today is NWSL, and there's no
/// Competition data model. When non-NWSL data exists, build the badge from it
/// and the dormant rendering below lights up with no card-layout changes.
struct CompetitionBadge {
    let label: String   // e.g. "CONCACAF W — Semifinal"
    let color: Color
}

struct MatchCard: View {
    let event: Event
    /// nil for ordinary NWSL matches (the only kind today). See CompetitionBadge.
    var badge: CompetitionBadge? = nil

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let badge { badgePill(badge) }
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 18) {
                    teamRow(event.homeCompetitor)
                    teamRow(event.awayCompetitor)
                }
                Spacer(minLength: 8)
                statusView
            }
            if hasInfoLine { infoLine }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .background(Color(.secondarySystemGroupedBackground))
        // 3px competition-color left accent, clipped to the rounded corners.
        // Dormant until a badge is supplied (see CompetitionBadge).
        .overlay(alignment: .leading) {
            if let badge {
                badge.color.frame(width: 3)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func badgePill(_ badge: CompetitionBadge) -> some View {
        Text(badge.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(badge.color.opacity(0.18), in: Capsule())
            .foregroundStyle(badge.color)
    }

    // Venue (always, when known) + broadcast (upcoming/live only — a finished
    // game's channel is moot). Mirrors how the NWSL/MLS apps surface per-game
    // stadium + TV info.
    private var hasInfoLine: Bool {
        event.venueName != nil || (event.statusState != "post" && event.broadcastName != nil)
    }

    private var infoLine: some View {
        HStack(spacing: 14) {
            if let venue = event.venueName {
                Label(venue, systemImage: "mappin.and.ellipse")
                    .lineLimit(1)
            }
            if event.statusState != "post", let channel = event.broadcastName {
                broadcastLabel(channel)
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
    }

    // The 📺 channel: a tappable "where to watch" link when we recognize the
    // broadcaster (opens its streaming page), otherwise a plain label. The whole
    // card is a NavigationLink, so the button takes hit-test priority for its own
    // area while taps elsewhere on the card still navigate to the match.
    @ViewBuilder
    private func broadcastLabel(_ channel: String) -> some View {
        if let url = BroadcastLink.url(for: channel) {
            Button {
                openURL(url)
            } label: {
                Label(channel, systemImage: "tv")
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
        } else {
            Label(channel, systemImage: "tv")
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func teamRow(_ competitor: Competitor?) -> some View {
        HStack(spacing: 12) {
            TeamLogo(urlString: competitor?.team?.logo, size: 34)
            // Fixed minWidth keeps home/away abbreviations aligned regardless
            // of logo load state — no horizontal shift as crests resolve.
            Text(competitor?.team?.abbreviation ?? competitor?.team?.shortDisplayName ?? "—")
                .font(.title3.weight(.medium))
                .frame(minWidth: 52, alignment: .leading)
            if showScores, let score = competitor?.score {
                // Rounded, monospaced digits echo the MatchDetailView header score.
                Text(score)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
            }
        }
    }

    private var showScores: Bool {
        event.statusState == "in" || event.statusState == "post"
    }

    @ViewBuilder
    private var statusView: some View {
        switch event.statusState {
        case "in":
            VStack(alignment: .trailing, spacing: 2) {
                Text("LIVE")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.red)
                if let clock = event.status?.displayClock {
                    Text(clock)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        case "post":
            Text(event.status?.type?.shortDetail ?? "FT")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        default:
            Text(kickoffTimeText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var kickoffTimeText: String {
        guard let kickoff = event.kickoff else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: kickoff)
    }
}
