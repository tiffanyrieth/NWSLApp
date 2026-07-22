//
//  MatchCard.swift
//  NWSLApp
//
//  One game as a self-contained card in ScheduleView — the redesign's "Color
//  Block" card (design-handoff `schedule-cards.jsx` → CardC). A team-color wash
//  bleeds in from each edge over the one card surface; big ring-free crests sit on
//  their own color side with the score beneath; the center column carries the
//  temporal state (cyan kickoff, pulsing red LIVE + orange clock, green FT). A
//  broadcast color chip + venue anchor the bottom rail.
//
//  Uniform height across states: the score band reserves its slot and the center
//  column holds a min height, so future cards match past/live cards down the list.
//
//  Honors design rule #1 (lives inside its card, no persistent overlays) and §0
//  (crest is the hero — 60pt, ring-free).
//

import MatchClockKit
import SwiftUI

struct MatchCard: View {
    let match: ScheduledMatch
    /// When the match data was last fetched (MatchStore.lastLoadedAt) — anchors the live
    /// minute's local tick. nil (e.g. previews) → fall back to ESPN's `displayClock` string.
    var anchor: Date? = nil
    private var event: Event { match.event }

    // Drives the pulsing LIVE dot (live matches only).
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 13) {
            // Competition label (tracked-caps) for non-NWSL matches — omitted on NWSL
            // (redundant on the home league). E.g. "SHEBELIEVES CUP", "INTERNATIONAL FRIENDLY".
            if let label = match.competition.displayLabel {
                Text(label.uppercased())
                    .dsFont(10, weight: .bold)
                    .tracking(0.6)
                    .foregroundStyle(Color.dsFgSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(alignment: .center, spacing: 0) {
                side(event.homeCompetitor, color: homeColor)
                centerColumn
                side(event.awayCompetitor, color: awayColor)
            }
            if hasRail { rail }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        // The team-color wash (the sanctioned match gradient at card scale) — now the shared
        // `TeamWashBackground` so Schedule + Predict draw the identical recipe.
        .background { TeamWashBackground(base: .dsBgCard, home: homeColor, away: awayColor) }
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous))
        .onAppear { if event.statusState == "in" { pulse = true } }
    }

    // MARK: - Sides (crest hero + score beneath)

    private func side(_ competitor: Competitor?, color: Color) -> some View {
        VStack(spacing: 8) {
            TeamLogo(urlString: competitor?.team?.logo,
                     teamAbbreviation: competitor?.team?.abbreviation,
                     size: 60)
            // Abbreviation directly below the crest, in the team's color — the
            // two-team-context rule (crest + ABBREVIATION, never crest-only). Matches
            // the Standings / match-detail convention (bold, tracked, team color).
            Text(competitor?.team?.abbreviation ?? "")
                .dsFont(14, weight: .bold)
                .tracking(0.3)
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize()
            // Fixed-height score band — reserved even on future cards so every state
            // is the same height.
            ZStack {
                if showScores, let score = competitor?.score {
                    Text(score)
                        .dsFont(32, weight: .heavy, design: .rounded, monospacedDigit: true)
                        .foregroundStyle(Color.dsFgPrimary)
                }
            }
            .frame(height: 34)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Center (temporal state)

    private var centerColumn: some View {
        VStack(spacing: 7) {
            statePill
            switch event.statusState {
            case "in":
                EmptyView()
            case "post":
                Text("FULL TIME")
                    .dsFont(11)
                    .tracking(0.3)
                    .foregroundStyle(Color.dsFgSecondary)
            default:
                // Cyan kickoff time — completes the temporal-color set with the
                // orange live clock and green FT.
                Text(kickoffTimeText)
                    .dsFont(22, weight: .bold, design: .rounded, monospacedDigit: true)
                    .foregroundStyle(Color.dsStateKickoff)
                    // At larger text the time would outgrow the center column and clip
                    // ("8:00…"); shrink to keep "8:00 PM" whole.
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(minHeight: 104)
    }

    @ViewBuilder
    private var statePill: some View {
        switch event.statusState {
        case "in":
            HStack(spacing: 5) {
                Circle()
                    .fill(Color.dsStateLive)
                    .frame(width: 7, height: 7)
                    .opacity(pulse ? 0.3 : 1)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
                Text("LIVE")
                    .dsFont(11, weight: .bold)
                    .tracking(0.6)
                    .foregroundStyle(Color.dsStateLive)
                // The live-clock guard (halftime → static HT, never tick through the break; live →
                // locally-ticking football minute "51'"/"45'+2'"; else ESPN's displayClock string)
                // lives once in MatchClockKit so a layout edit here can't reintroduce a mid-match bug.
                LiveMatchClockView(
                    display: .resolve(
                        statusState: event.statusState, isHalftime: event.isHalftime,
                        clockSeconds: event.status?.clock, period: event.status?.period, anchor: anchor,
                        halftimeLabel: "HT", fallback: event.status?.displayClock)
                ) { label in
                    Text(label)
                        .dsFont(11, weight: .bold, monospacedDigit: true)
                        .foregroundStyle(Color.dsStateClock)
                }
            }
        case "post":
            Text("FT")
                .dsFont(11, weight: .bold)
                .tracking(0.6)
                .foregroundStyle(Color.dsStateFinal)
        default:
            Text("KICKOFF")
                .dsFont(11, weight: .bold)
                .tracking(0.6)
                .foregroundStyle(Color.dsStateKickoff)
        }
    }

    // MARK: - Bottom rail (broadcast chip + venue)

    // Resolved primary channel — curated English home for comps ESPN only carries
    // in Spanish (Champions Cup → Paramount+), else ESPN's own value.
    private var broadcastName: String? {
        match.competition.primaryBroadcastOverride ?? event.broadcastName
    }

    // Kept on all states, including finished games: the broadcast chip helps fans
    // find (and re-find) where a match aired — NWSL games are hard to track down.
    private var hasRail: Bool {
        broadcastName != nil || event.venueName != nil
    }

    private var rail: some View {
        HStack(spacing: 10) {
            if let channel = broadcastName {
                BroadcastChip(name: channel)
            }
            if let venue = event.venueName {
                Text(venue)
                    .dsFont(11.5)
                    .foregroundStyle(Color.dsFgSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private var showScores: Bool {
        event.statusState == "in" || event.statusState == "post"
    }

    // Team colors resolved by abbreviation via the design palette — the same
    // authoritative source as Standings (the scoreboard competitor carries no
    // color of its own).
    // NWSL clubs, women's national teams, and known Champions Cup foreign clubs get
    // their brand color; anything still unknown renders NEUTRAL gray (Color.teamColor).
    private var homeColor: Color { Color.teamColor(for: event.homeCompetitor) }
    private var awayColor: Color { Color.teamColor(for: event.awayCompetitor) }

    // Cached: a MatchCard body evaluates per card while scrolling the full-season schedule, so a
    // per-body DateFormatter alloc was scroll-hot. Static = one instance, reused across all cards.
    private static let kickoffTimeFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = .current; f.timeZone = .current
        f.timeStyle = .short; f.dateStyle = .none; return f
    }()

    private var kickoffTimeText: String {
        guard let kickoff = event.kickoff else { return "—" }
        return Self.kickoffTimeFormatter.string(from: kickoff)
    }
}
