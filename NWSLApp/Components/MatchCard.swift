//
//  MatchCard.swift
//  NWSLApp
//
//  One game as a self-contained card in ScheduleView (MLS-app style). V2 design
//  refresh (design handoff `UIComponents.jsx` → `UIMatchCard`): team-color RING
//  CRESTS echo the MatchDetail header at card scale, the status column is set off
//  by a full-height hairline, and the live clock burns orange.
//
//  Left: stacked home/away rows, each the club crest (shown bare via TeamLogo —
//  a team crest is a self-contained shape, no ring) + abbreviation, plus scores
//  once the match is in progress or final. Right (hairline-separated): kickoff
//  time for upcoming, "LIVE" + clock for in-progress, or "FT" for finished.
//
//  Honors design rule #1: lives entirely inside its card, no overlays.
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
        VStack(alignment: .leading, spacing: DS.space6) {
            if let badge { badgePill(badge) }
            HStack(spacing: DS.space6) {
                VStack(alignment: .leading, spacing: DS.space7) {
                    teamRow(event.homeCompetitor)
                    teamRow(event.awayCompetitor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Full-height hairline divider, then the fixed status column.
                Rectangle()
                    .fill(Color.dsSeparator)
                    .frame(width: DS.hairline)
                statusView
                    .frame(width: 52)
                    .frame(maxHeight: .infinity)
            }
            .fixedSize(horizontal: false, vertical: true)
            if hasInfoLine { infoLine }
        }
        .padding(DS.cardPadding)
        .background(Color.dsBgCard)
        // 3px competition-color left accent, clipped to the rounded corners.
        // Dormant until a badge is supplied (see CompetitionBadge).
        .overlay(alignment: .leading) {
            if let badge {
                badge.color.frame(width: 3)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous))
    }

    private func badgePill(_ badge: CompetitionBadge) -> some View {
        Text(badge.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, DS.space4)
            .padding(.vertical, 3)
            .background(badge.color.opacity(0.18), in: Capsule())
            .foregroundStyle(badge.color)
    }

    @ViewBuilder
    private func teamRow(_ competitor: Competitor?) -> some View {
        let abbr = competitor?.team?.abbreviation ?? competitor?.team?.shortDisplayName ?? "—"
        HStack(spacing: DS.space5) {
            TeamLogo(urlString: competitor?.team?.logo, teamAbbreviation: competitor?.team?.abbreviation, size: 34)
            // Fixed minWidth keeps home/away abbreviations aligned regardless of
            // crest load state — no horizontal shift as logos resolve.
            Text(abbr)
                .font(.system(size: 20, weight: .medium))
                .frame(minWidth: 44, alignment: .leading)
            if showScores, let score = competitor?.score {
                Text(score)
                    .font(.system(size: 17, weight: .bold))
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
            VStack(spacing: 2) {
                Text("LIVE")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.dsLive)
                if let clock = event.status?.displayClock {
                    Text(clock)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.dsStateClock)   // orange live clock
                        .monospacedDigit()
                }
            }
        case "post":
            Text(event.status?.type?.shortDetail ?? "FT")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.dsFgSecondary)
        default:
            Text(kickoffTimeText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.dsFgPrimary)
        }
    }

    // Venue (always, when known) + broadcast (upcoming/live only — a finished
    // game's channel is moot). 📍/📺 emoji match the design mockups.
    private var hasInfoLine: Bool {
        event.venueName != nil || (event.statusState != "post" && event.broadcastName != nil)
    }

    private var infoLine: some View {
        HStack(spacing: DS.space7) {
            if let venue = event.venueName {
                Text("📍 \(venue)")
                    .lineLimit(1)
                    .foregroundStyle(Color.dsFgSecondary)
            }
            if event.statusState != "post", let channel = event.broadcastName {
                broadcastLabel(channel)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 12))
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
                Text("📺 \(channel)").lineLimit(1)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.dsAccent)
        } else {
            Text("📺 \(channel)")
                .lineLimit(1)
                .foregroundStyle(Color.dsFgSecondary)
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
