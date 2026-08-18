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
                    .dsFont(12, weight: .bold)
                    .tracking(0.6)
                    .foregroundStyle(Color.dsFgSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(alignment: .center, spacing: 0) {
                side(event.homeCompetitor, color: homeColor)
                centerColumn
                side(event.awayCompetitor, color: awayColor)
            }
            infoBlock
        }
        .padding(14)
        // A shared height FLOOR so past (score, 1 info line) and future (no score, venue+TV two
        // lines) land at the SAME height. A past card's crest+score column stands at ~185pt on its
        // own; a future card has no score, so its two-line venue/TV block leaves it ~11pt short — the
        // floor pads that gap up so future == past and the overview stays uniform state-to-state. The
        // freed score-band space is thus REUSED for the venue/TV second line (not deleted), so a
        // future card carries both WITHOUT shrinking below its past neighbors (owner 2026-08-13; the
        // 08-12 pass mis-set this to 174 and future came out short). A LIVE card carries score + venue
        // + TV, exceeds the floor, and rides intentionally taller ("a game's on right now"). Floor,
        // not fixed height: at larger Dynamic Type the content grows past it and it yields.
        .frame(maxWidth: .infinity, minHeight: 186)
        // The team-color wash (the sanctioned match gradient at card scale) — now the shared
        // `TeamWashBackground` so Schedule + Predict draw the identical recipe.
        .background { TeamWashBackground(base: .dsBgCard, home: homeColor, away: awayColor) }
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous))
        .onAppear { if event.statusState == "in" { pulse = true } }
        // One VoiceOver element with a curated sentence instead of the garbled fragment concat
        // ("[comp] · ABBR · 4 · LIVE · 51' · ABBR · 1 · venue · channel"). `.ignore` because the
        // crest/score/clock are drawn/animated visuals — the label is rebuilt from the model, so
        // the live minute reads as words, not "51 apostrophe". The card sits in a NavigationLink,
        // so VoiceOver adds the button trait + "view details" action on top of this.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(voiceOverLabel)
    }

    // Curated VoiceOver label — "Louisville Racing 4, Boston 1, full time, at Lynn Family Stadium".
    private var voiceOverLabel: String {
        let home = event.homeCompetitor?.team?.displayName ?? event.homeCompetitor?.team?.abbreviation ?? "Home"
        let away = event.awayCompetitor?.team?.displayName ?? event.awayCompetitor?.team?.abbreviation ?? "Away"
        var parts: [String] = []
        if let label = match.competition.displayLabel { parts.append(label) }
        switch event.statusState {
        case "in":
            let hs = event.homeCompetitor?.score ?? "0"
            let aw = event.awayCompetitor?.score ?? "0"
            parts.append("\(home) \(hs), \(away) \(aw), \(event.isHalftime ? "halftime" : "live")")
        case "post":
            let hs = event.homeCompetitor?.score ?? "0"
            let aw = event.awayCompetitor?.score ?? "0"
            let state = event.isFinalResult ? "full time"
                : (event.status?.type?.description ?? "suspended").lowercased()
            parts.append("\(home) \(hs), \(away) \(aw), \(state)")
        default:
            parts.append("\(home) versus \(away), kickoff \(kickoffTimeText)")
        }
        if let venue = event.venueName { parts.append("at \(venue)") }
        // Channel is shown on future/live cards only (a finished game drops it).
        if event.statusState != "post", let channel = broadcastName { parts.append("on \(channel)") }
        return parts.joined(separator: ", ")
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
            // Score UNDER each crest — only when there IS one (past/live). Held to a fixed 34pt band
            // (so the big 32pt glyph can't balloon a past card past its neighbors). No band at all on
            // a future card: that freed vertical space is reused by the venue/TV info block below, so
            // a future card carries both WITHOUT growing (owner 2026-08-12).
            if showScores, let score = competitor?.score {
                Text(score)
                    .dsFont(32, weight: .heavy, design: .rounded, monospacedDigit: true)
                    .foregroundStyle(Color.dsFgPrimary)
                    .frame(height: 34)
            }
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
                // A suspended/abandoned match also reports `post` — show ESPN's own label
                // ("Suspended") rather than claiming FULL TIME on a match still to be finished.
                Text(event.isFinalResult
                     ? "FULL TIME"
                     : (event.status?.type?.description ?? "SUSPENDED").uppercased())
                    .dsFont(12)
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
        .frame(minHeight: 88)
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
                    .dsFont(12, weight: .bold)
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
                        .dsFont(12, weight: .bold, monospacedDigit: true)
                        .foregroundStyle(Color.dsStateClock)
                }
            }
        case "post":
            // "Susp" (ESPN's own shortDetail) instead of a green FT on a match that hasn't finished.
            Text(event.isFinalResult ? "FT" : (event.status?.type?.shortDetail ?? "SUSP"))
                .dsFont(12, weight: .bold)
                .tracking(0.6)
                .foregroundStyle(event.isFinalResult ? Color.dsStateFinal : Color.dsWarning)
        default:
            Text("KICKOFF")
                .dsFont(12, weight: .bold)
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

    // Venue + broadcast, STATE-AWARE and centered (owner 2026-08-12 redesign). Every element is a
    // LONE centered element (venue line on its own, chip on its own) so nothing drifts card-to-card:
    // a lone centered element pins to the card's axis, which kills the old "chip floats left/right
    // depending on the venue length" tell. Both MLS and NWSL lay it out exactly this way.
    //   • PAST → venue only, one line. The TV chip is dropped: a finished game's channel isn't
    //     actionable (no NWSL archive deal), and it still lives on the match-detail screen.
    //   • FUTURE → venue + TV on two centered lines, dropped into the score space a scoreless card
    //     already reserves, so the card does NOT grow.
    //   • LIVE → venue + TV two lines PLUS the score, so it rides a touch taller — an intentional
    //     "there's a game on right now" flag.
    // Height stays uniform WITHIN a state (all lone-centered, nothing float-dependent).
    @ViewBuilder
    private var infoBlock: some View {
        VStack(spacing: 6) {
            venueLine
            if event.statusState != "post", let channel = broadcastName {
                BroadcastChip(name: channel)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 21)
    }

    // A lone centered "📍 Venue" line. Wraps to two lines rather than shrinking below the readable
    // floor (the venue is readable prose, so it can't scale under 12pt) — the rare mouthful
    // ("Northwestern Medicine Field at Martin Stadium") takes a second centered line instead of
    // truncating; every ordinary venue is one line.
    @ViewBuilder
    private var venueLine: some View {
        if let venue = event.venueName {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.dsFgSecondary)
                Text(venue)
                    .dsFont(13)
                    .foregroundStyle(Color.dsFgSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
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
    private var homeColor: Color { Color.teamColor(for: event.homeCompetitor, isNational: match.competition.isNational) }
    private var awayColor: Color { Color.teamColor(for: event.awayCompetitor, isNational: match.competition.isNational) }

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
