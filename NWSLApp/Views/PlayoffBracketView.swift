//
//  PlayoffBracketView.swift
//  NWSLApp
//
//  The "Bracket" segment of the postseason Standings tab: the whole bracket as a VERTICAL,
//  round-grouped list — NEVER a horizontal tree (unreadable upright on a phone). Round
//  headers carry a status dot (cyan = current/upcoming, green = complete) with the left
//  connecting line, per Bracket Battle's overview. Each matchup renders via the shared
//  PlayoffMatchupRow — MatchCard's anatomy (two-team wash, crest heroes, center state
//  column, BroadcastChip rail) so a playoff game reads identically to a Schedule game.
//  Tapping a placed matchup opens MatchDetailView.
//

import SwiftUI

struct PlayoffBracketView: View {
    let bracket: PlayoffBracket
    /// Resolve a matchup's eventID → open MatchDetailView (handled by StandingsView).
    let onOpenMatch: (String) -> Void

    @Environment(ClubStore.self) private var clubs
    @Environment(FollowingStore.self) private var following

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let ctx = winContext { winContextCard(ctx) }
            ForEach(bracket.rounds) { round in
                roundSection(round)
            }
            footerNote
        }
        .padding(.horizontal, DS.pagePadding)
        .padding(.top, 4)
    }

    // MARK: Win → context (personal, top of the bracket)

    private var followedAlive: String? {
        followedAbbrs.first { bracket.isAlive($0) }
    }

    private var winContext: String? {
        guard let team = followedAlive,
              let step = bracket.path(forAbbreviation: team)?.first(where: { $0.winContext != nil })
        else { return nil }
        return step.winContext.map { humanize($0) }
    }

    private func winContextCard(_ text: String) -> some View {
        let accent = color(followedAlive ?? "")
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Win →").dsFont(13, weight: .heavy).foregroundStyle(accent)
            Text(text).dsFont(13).foregroundStyle(Color.dsFgSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: DS.radiusLg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusLg, style: .continuous).strokeBorder(accent.opacity(0.25)))
        .padding(.bottom, 8)
    }

    // MARK: Round section (header + rows + connecting line)

    private func roundSection(_ round: PlayoffRound) -> some View {
        let status = roundStatus(round)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(status.color).frame(width: 8, height: 8)
                Text(round.title).trackedCaps(size: 13, weight: .heavy, color: status.color)
                Text("· \(status.note)").dsFont(12).foregroundStyle(Color.dsFgTertiary)
                Spacer(minLength: 0)
            }
            VStack(spacing: DS.cardGap) {
                ForEach(bracket.matchups(in: round)) { m in matchupRow(m) }
            }
            .padding(.leading, 16)
            .overlay(Rectangle().fill(status.color.opacity(0.3)).frame(width: 2), alignment: .leading)
        }
        .padding(.top, 16)
    }

    @ViewBuilder
    private func matchupRow(_ m: PlayoffMatchup) -> some View {
        let row = PlayoffMatchupRow(
            matchup: m,
            homeClub: m.home.abbreviation.flatMap { clubs.club(forAbbreviation: $0) },
            awayClub: m.away.abbreviation.flatMap { clubs.club(forAbbreviation: $0) },
            followedAbbreviations: followedAbbrs
        )
        if let id = m.eventID, m.isResolved {
            Button { onOpenMatch(id) } label: { row }.buttonStyle(.plain)
        } else {
            row    // projected / TBD rows aren't tappable (no event yet)
        }
    }

    private var footerNote: some View {
        Text("Higher seed hosts through the semifinal. Tap a matchup for full details.")
            .dsFont(11.5).multilineTextAlignment(.center).foregroundStyle(Color.dsFgSecondary)
            .frame(maxWidth: .infinity).padding(.horizontal, 24).padding(.vertical, 20)
    }

    // MARK: Round status

    private struct RoundStatus { let color: Color; let note: String }

    private func roundStatus(_ round: PlayoffRound) -> RoundStatus {
        let ms = bracket.matchups(in: round)
        let played = ms.filter { $0.isFinal }.count
        if !ms.isEmpty, played == ms.count {
            return RoundStatus(color: .dsStateFinal, note: "Complete")
        }
        if ms.contains(where: { $0.state == .live }) {
            return RoundStatus(color: .dsStateLive, note: "Live")
        }
        if let range = dateRange(ms) {
            return RoundStatus(color: .dsStateKickoff, note: range)
        }
        return RoundStatus(color: .dsStateKickoff, note: "Upcoming")
    }

    // MARK: Helpers — followed teams, colors, dates

    private var followedAbbrs: Set<String> {
        Set(bracket.seeds.keys.filter { isFollowed($0) })
    }
    private func isFollowed(_ abbr: String?) -> Bool {
        guard let abbr, let club = clubs.club(forAbbreviation: abbr) else { return false }
        return following.isFollowing(club)
    }
    private func color(_ abbr: String) -> Color {
        guard let hex = DesignTeamColors.displayHex(for: abbr) else { return .dsAccent }
        return Color.teamFillOnDark(hex: hex)
    }

    /// Replace bare abbreviations in a Win→ phrase with full club names where we can.
    private func humanize(_ phrase: String) -> String {
        var out = phrase
        for abbr in bracket.seeds.keys {
            if let name = clubs.club(forAbbreviation: abbr)?.displayName {
                out = out.replacingOccurrences(of: " \(abbr) ", with: " \(name) ")
                if out.hasSuffix(" \(abbr)") { out = String(out.dropLast(abbr.count)) + name }
            }
        }
        return out
    }

    /// Round-header date range, Schedule-style parts ("Nov 7–9").
    private func dateRange(_ ms: [PlayoffMatchup]) -> String? {
        let dates = ms.compactMap { $0.kickoff }.sorted()
        guard let first = dates.first, let last = dates.last else { return nil }
        let f = DateFormatter(); f.locale = .current; f.timeZone = .current; f.dateFormat = "MMM d"
        let d = DateFormatter(); d.locale = .current; d.timeZone = .current; d.dateFormat = "d"
        if Calendar.current.isDate(first, inSameDayAs: last) { return f.string(from: first) }
        let sameMonth = Calendar.current.component(.month, from: first) == Calendar.current.component(.month, from: last)
        return sameMonth ? "\(f.string(from: first))–\(d.string(from: last))" : "\(f.string(from: first))–\(f.string(from: last))"
    }
}
