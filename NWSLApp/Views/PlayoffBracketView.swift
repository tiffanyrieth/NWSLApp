//
//  PlayoffBracketView.swift
//  NWSLApp
//
//  The "Bracket" segment of the postseason Standings tab: the whole bracket as a VERTICAL,
//  round-grouped list — NEVER a horizontal tree (unreadable upright on a phone). It lifts the
//  proven visual language of Bracket Battle's "bracket so far" overview (round header + status
//  dot, left connecting line, round-grouped rows, TBD placeholders) and re-expresses it for
//  real teams: crest + abbreviation + seed per side, scores for finished games, plus a footer
//  row the game doesn't have — date · time · TV · venue. Your teams get an accent border + ★.
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
        return step.winContext.map { humanize($0, team: team) }
    }

    private func winContextCard(_ text: String) -> some View {
        let accent = color(followedAlive ?? "")
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Win →").dsFont(12, weight: .heavy).foregroundStyle(accent)
            Text(text).dsFont(12).foregroundStyle(Color.dsFgSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(accent.opacity(0.25)))
        .padding(.bottom, 8)
    }

    // MARK: Round section (header + rows + connecting line)

    private func roundSection(_ round: PlayoffRound) -> some View {
        let status = roundStatus(round)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(status.color).frame(width: 8, height: 8)
                Text(round.title).dsFont(13, weight: .heavy).tracking(1.2).foregroundStyle(status.color)
                Text("· \(status.note)").dsFont(12).foregroundStyle(Color.dsFgTertiary)
                Spacer(minLength: 0)
            }
            VStack(spacing: 8) {
                ForEach(bracket.matchups(in: round)) { m in matchupRow(m) }
            }
            .padding(.leading, 16)
            .overlay(Rectangle().fill(status.color.opacity(0.3)).frame(width: 2), alignment: .leading)
        }
        .padding(.top, 16)
    }

    // MARK: Matchup row

    @ViewBuilder
    private func matchupRow(_ m: PlayoffMatchup) -> some View {
        let mine = m.contains(where: followedAbbrs)
        let accent = mine ? color(m.mineAbbr(in: followedAbbrs) ?? "") : Color.clear
        let card = VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 4) {
                teamSide(m.home, align: .leading, isFinal: m.isFinal)
                Text("vs").dsFont(11, weight: .bold).foregroundStyle(Color.dsFgQuaternary).padding(.horizontal, 2)
                teamSide(m.away, align: .trailing, isFinal: m.isFinal)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            Rectangle().fill(Color.dsSeparator).frame(height: DS.hairline)
            infoRow(m)
        }
        .background(Color.dsBgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(mine ? accent.opacity(0.45) : Color.clear, lineWidth: 1)
        )

        if let id = m.eventID, m.isResolved {
            Button { onOpenMatch(id) } label: { card }.buttonStyle(.plain)
        } else {
            card    // projected / TBD rows aren't tappable (no event yet)
        }
    }

    /// One side: crest + abbr + seed, and (finished game) the score. Loser dimmed.
    private func teamSide(_ side: BracketSide, align: HorizontalAlignment, isFinal: Bool) -> some View {
        let leading = align == .leading
        let club = side.abbreviation.flatMap { clubs.club(forAbbreviation: $0) }
        let dimmed = isFinal && !side.isWinner && !side.isTBD
        return HStack(spacing: 8) {
            if leading { crest(side, club: club) }
            VStack(alignment: leading ? .leading : .trailing, spacing: 1) {
                Text(side.abbreviation ?? "TBD")
                    .dsFont(14, weight: side.isWinner && isFinal ? .heavy : .bold)
                    .foregroundStyle(side.isTBD ? Color.dsFgQuaternary : (club?.accentColor ?? .dsFgPrimary))
                if let seed = side.seed {
                    Text("#\(seed) seed").dsFont(9, weight: .semibold).foregroundStyle(Color.dsFgTertiary)
                }
            }
            if isFinal, let score = side.score {
                Text("\(score)")
                    .dsFont(18, weight: .heavy, monospacedDigit: true)
                    .foregroundStyle(side.isWinner ? Color.dsFgPrimary : Color.dsFgTertiary)
                    .frame(minWidth: 16, alignment: leading ? .leading : .trailing)
            }
            if !leading { crest(side, club: club) }
        }
        .opacity(dimmed ? 0.45 : 1)
        .frame(maxWidth: .infinity, alignment: leading ? .leading : .trailing)
    }

    /// Prominent crest (crest-prominence rule — larger than the game's text-only rows).
    @ViewBuilder
    private func crest(_ side: BracketSide, club: Club?) -> some View {
        if side.isTBD {
            Circle().fill(Color.dsBgTertiary).frame(width: 34, height: 34)
                .overlay(Text("?").dsFont(14, weight: .bold).foregroundStyle(Color.dsFgQuaternary))
        } else {
            ZStack(alignment: .topTrailing) {
                TeamLogo(urlString: club?.logoURL, teamAbbreviation: side.abbreviation, size: 34)
                if isFollowed(side.abbreviation) {
                    Text("★").dsFont(9).foregroundStyle(color(side.abbreviation ?? ""))
                        .offset(x: 4, y: -4)
                }
            }
        }
    }

    /// The added footer: date · time · TV pill · venue, or a green "Full Time" for finals.
    private func infoRow(_ m: PlayoffMatchup) -> some View {
        HStack(spacing: 8) {
            if m.state == .live {
                Text("● LIVE").dsFont(10, weight: .heavy).foregroundStyle(Color.dsStateLive)
                if let b = m.broadcast { broadcastPill(b) }
                if let v = m.venue { dot; Text(v).dsFont(10).foregroundStyle(Color.dsFgTertiary).lineLimit(1) }
            } else if m.isFinal {
                Text("Full Time").dsFont(10, weight: .semibold).foregroundStyle(Color.dsStateFinal)
                if let v = m.venue { dot; Text(v).dsFont(10).foregroundStyle(Color.dsFgTertiary).lineLimit(1) }
            } else if m.isResolved || m.kickoff != nil {
                let today = isToday(m.kickoff)
                Text(today ? "Today" : (dateText(m.kickoff) ?? "Upcoming"))
                    .dsFont(10, weight: .semibold)
                    .foregroundStyle(today ? Color.dsStateClock : Color.dsFgSecondary)
                if let t = timeText(m.kickoff) { Text(t).dsFont(10, weight: .semibold).foregroundStyle(Color.dsFgPrimary) }
                if let b = m.broadcast { broadcastPill(b) }
                if let v = m.venue { dot; Text(v).dsFont(10).foregroundStyle(Color.dsFgTertiary).lineLimit(1) }
            } else {
                Text("Matchup TBD").dsFont(10, weight: .semibold).foregroundStyle(Color.dsFgTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private var dot: some View { Text("·").dsFont(10).foregroundStyle(Color.dsFgTertiary) }

    private func broadcastPill(_ name: String) -> some View {
        Text(name).dsFont(9, weight: .bold).foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Color.dsBgTertiary, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
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
        // date range across this round's kickoffs, else "Upcoming".
        if let range = dateRange(ms) {
            let color: Color = ms.contains { isToday($0.kickoff) } ? .dsStateClock : .dsStateKickoff
            return RoundStatus(color: color, note: range)
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
    private func color(_ abbr: String) -> Color { clubs.club(forAbbreviation: abbr)?.accentColor ?? .dsAccent }

    /// Replace bare abbreviations in a Win→ phrase with full club names where we can.
    private func humanize(_ phrase: String, team: String) -> String {
        var out = phrase
        for abbr in bracket.seeds.keys {
            if let name = clubs.club(forAbbreviation: abbr)?.displayName {
                out = out.replacingOccurrences(of: " \(abbr) ", with: " \(name) ")
                if out.hasSuffix(" \(abbr)") { out = String(out.dropLast(abbr.count)) + name }
            }
        }
        return out
    }

    private func dateText(_ date: Date?) -> String? {
        guard let date else { return nil }
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f.string(from: date)
    }
    private func timeText(_ date: Date?) -> String? {
        guard let date else { return nil }
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none; return f.string(from: date)
    }
    private func isToday(_ date: Date?) -> Bool {
        guard let date else { return false }
        return Calendar.current.isDateInToday(date)
    }
    private func dateRange(_ ms: [PlayoffMatchup]) -> String? {
        let dates = ms.compactMap { $0.kickoff }.sorted()
        guard let first = dates.first, let last = dates.last else { return nil }
        let f = DateFormatter(); f.dateFormat = "MMM d"
        let d = DateFormatter(); d.dateFormat = "d"
        if Calendar.current.isDate(first, inSameDayAs: last) { return f.string(from: first) }
        let sameMonth = Calendar.current.component(.month, from: first) == Calendar.current.component(.month, from: last)
        return sameMonth ? "\(f.string(from: first))–\(d.string(from: last))" : "\(f.string(from: first))–\(f.string(from: last))"
    }
}

// Small conveniences on the matchup for followed-team checks.
private extension PlayoffMatchup {
    func contains(where followed: Set<String>) -> Bool {
        (home.abbreviation.map(followed.contains) ?? false) || (away.abbreviation.map(followed.contains) ?? false)
    }
    func mineAbbr(in followed: Set<String>) -> String? {
        if let h = home.abbreviation, followed.contains(h) { return h }
        if let a = away.abbreviation, followed.contains(a) { return a }
        return nil
    }
}
