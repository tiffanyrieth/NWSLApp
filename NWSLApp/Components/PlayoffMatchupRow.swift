//
//  PlayoffMatchupRow.swift
//  NWSLApp
//
//  One playoff matchup as a card, shared by the Bracket and Your Path segments — built on
//  MatchCard's EXACT anatomy so a playoff game reads identically to a Schedule game
//  (the "tab-flip test"): two-team color wash over dsBgCard, ring-free 60pt crest heroes
//  with the abbreviation + score beneath on each side, the temporal state in the CENTER
//  column (cyan KICKOFF + time / pulsing red LIVE / green FT + FULL TIME), and a bottom
//  rail with the shared BroadcastChip + venue.
//
//  Playoff-only additions (the concept's semantics, deliberately kept):
//   • a small seed line under each abbreviation ("#2 seed"),
//   • TBD sides (placeholder circle) for unplaced slots,
//   • a team-accent border + ★ when a followed team is in the matchup,
//   • the ELIMINATED side dims to 45% with a muted score — owner decision: in a bracket,
//     "who advanced" is the point (MatchCard keeps both sides full-strength; this is the
//     one documented deviation).
//

import SwiftUI

struct PlayoffMatchupRow: View {
    let matchup: PlayoffMatchup
    /// Clubs for the two sides (crest URL fallback only — colors come from DesignTeamColors
    /// like MatchCard). nil is fine: TeamLogo renders the bundled crest by abbreviation.
    var homeClub: Club? = nil
    var awayClub: Club? = nil
    /// Followed-team abbreviations in this matchup (drives the accent border + ★).
    var followedAbbreviations: Set<String> = []

    @State private var pulse = false

    private var yoursAbbr: String? {
        [matchup.home.abbreviation, matchup.away.abbreviation]
            .compactMap { $0 }
            .first { followedAbbreviations.contains($0) }
    }

    var body: some View {
        VStack(spacing: 13) {
            HStack(alignment: .center, spacing: 0) {
                side(matchup.home, club: homeClub, color: teamColor(matchup.home.abbreviation))
                centerColumn
                side(matchup.away, club: awayClub, color: teamColor(matchup.away.abbreviation))
            }
            if hasRail { rail }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                Color.dsBgCard
                // MatchCard's sanctioned two-team wash: home @18% from the left, away @18%
                // from the right, clear through the middle, tilted ~100°.
                LinearGradient(
                    stops: [
                        .init(color: washColor(matchup.home).opacity(0.18), location: 0.0),
                        .init(color: washColor(matchup.home).opacity(0.0), location: 0.34),
                        .init(color: washColor(matchup.away).opacity(0.0), location: 0.66),
                        .init(color: washColor(matchup.away).opacity(0.18), location: 1.0),
                    ],
                    startPoint: UnitPoint(x: 0, y: 0.42),
                    endPoint: UnitPoint(x: 1, y: 0.58)
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous))
        .overlay {
            if let yours = yoursAbbr {
                RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous)
                    .strokeBorder(teamColor(yours).opacity(0.45), lineWidth: 1)
            }
        }
        .onAppear { if matchup.state == .live { pulse = true } }
    }

    // MARK: - Sides (crest hero + abbr + seed + score band, per MatchCard)

    private func side(_ bside: BracketSide, club: Club?, color: Color) -> some View {
        // The eliminated side dims (playoff-only semantic; see header comment).
        let dimmed = matchup.isFinal && !bside.isWinner && !bside.isTBD
        return VStack(spacing: 8) {
            crest(bside, club: club, color: color)
            Text(bside.abbreviation ?? "TBD")
                .dsFont(14, weight: .bold)
                .tracking(0.3)
                .foregroundStyle(bside.isTBD ? Color.dsFgQuaternary : color)
                .lineLimit(1)
                .fixedSize()
            // Seed line — the playoff addition, quiet under the abbreviation.
            if let seed = bside.seed {
                Text("#\(seed) seed")
                    .dsFont(11, weight: .semibold)
                    .foregroundStyle(Color.dsFgSecondary)
            }
            // Fixed-height score band (reserved on every state so rows align, like MatchCard).
            ZStack {
                if showScores, let score = bside.score {
                    Text("\(score)")
                        .dsFont(32, weight: .heavy, design: .rounded, monospacedDigit: true)
                        .foregroundStyle(bside.isWinner || !matchup.isFinal ? Color.dsFgPrimary : Color.dsFgTertiary)
                }
            }
            .frame(height: 34)
        }
        .frame(maxWidth: .infinity)
        .opacity(dimmed ? 0.45 : 1)
    }

    @ViewBuilder
    private func crest(_ bside: BracketSide, club: Club?, color: Color) -> some View {
        if bside.isTBD {
            Circle().fill(Color.dsBgTertiary)
                .frame(width: 60, height: 60)
                .overlay(Text("?").dsFont(22, weight: .bold).foregroundStyle(Color.dsFgQuaternary))
        } else {
            ZStack(alignment: .topTrailing) {
                TeamLogo(urlString: club?.logoURL, teamAbbreviation: bside.abbreviation, size: 60)
                if let abbr = bside.abbreviation, followedAbbreviations.contains(abbr) {
                    Text("★").dsFont(12).foregroundStyle(color).offset(x: 6, y: -3)
                }
            }
        }
    }

    // MARK: - Center (temporal state, per MatchCard)

    private var centerColumn: some View {
        VStack(spacing: 7) {
            statePill
            switch matchup.state {
            case .live:
                EmptyView()
            case .post:
                Text("FULL TIME")
                    .dsFont(11)
                    .tracking(0.3)
                    .foregroundStyle(Color.dsFgSecondary)
            case .pre:
                if matchup.kickoff != nil {
                    Text(kickoffTimeText)
                        .dsFont(22, weight: .bold, design: .rounded, monospacedDigit: true)
                        .foregroundStyle(Color.dsStateKickoff)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                } else {
                    // Projected matchup — no fixture yet.
                    Text("TBD")
                        .dsFont(22, weight: .bold, design: .rounded)
                        .foregroundStyle(Color.dsFgQuaternary)
                }
            }
        }
        .frame(minHeight: 104)
    }

    @ViewBuilder
    private var statePill: some View {
        switch matchup.state {
        case .live:
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
            }
        case .post:
            Text("FT")
                .dsFont(11, weight: .bold)
                .tracking(0.6)
                .foregroundStyle(Color.dsStateFinal)
        case .pre:
            Text(matchup.kickoff != nil ? "KICKOFF" : "MATCHUP")
                .dsFont(11, weight: .bold)
                .tracking(0.6)
                .foregroundStyle(matchup.kickoff != nil ? Color.dsStateKickoff : Color.dsFgTertiary)
        }
    }

    // MARK: - Bottom rail (date + BroadcastChip + venue, per MatchCard)

    private var hasRail: Bool {
        matchup.broadcast != nil || matchup.venue != nil || (matchup.state == .pre && matchup.kickoff != nil)
    }

    private var rail: some View {
        HStack(spacing: 10) {
            // The bracket lists many days in one view (unlike Schedule's day headers), so the
            // date rides the rail on upcoming games. "TODAY" gets kickoff cyan — the temporal
            // color for "future", NOT the orange live clock.
            if matchup.state == .pre, matchup.kickoff != nil {
                Text(dateLabel)
                    .dsFont(11, weight: .bold)
                    .tracking(0.6)
                    .foregroundStyle(isToday ? Color.dsStateKickoff : Color.dsFgSecondary)
            }
            if let channel = matchup.broadcast {
                BroadcastChip(name: channel)
            }
            if let venue = matchup.venue {
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

    private var showScores: Bool { matchup.state == .live || matchup.state == .post }

    private var isToday: Bool {
        matchup.kickoff.map { Calendar.current.isDateInToday($0) } ?? false
    }

    /// "TODAY" or the Schedule day-header format ("SAT · NOV 8"), uppercased.
    private var dateLabel: String {
        guard let kickoff = matchup.kickoff else { return "" }
        if isToday { return "TODAY" }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateFormat = "EEE '·' MMM d"
        return formatter.string(from: kickoff).uppercased()
    }

    private var kickoffTimeText: String {
        guard let kickoff = matchup.kickoff else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: kickoff)
    }

    /// Team color per MatchCard's convention: DesignTeamColors by abbreviation, adjusted for
    /// dark backgrounds; unknown → neutral gray. (NOT club.accentColor — this is the match-
    /// surface source of truth.)
    private func teamColor(_ abbreviation: String?) -> Color {
        guard let hex = DesignTeamColors.displayHex(for: abbreviation) else {
            return Color(hex: "8E8E93")
        }
        return Color.teamFillOnDark(hex: hex)
    }

    private func washColor(_ bside: BracketSide) -> Color {
        bside.isTBD ? Color(hex: "8E8E93") : teamColor(bside.abbreviation)
    }
}
