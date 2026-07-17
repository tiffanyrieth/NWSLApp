//
//  PlayoffPathView.swift
//  NWSLApp
//
//  The "Your Path" segment — the default during the postseason when a followed team is in the
//  bracket. For each followed playoff team: a hero header, a vertical team-color timeline from
//  its current round to the Championship, and — the feature's whole point — a plain-language
//  "Win → face X in the [round]" line under each step. Matchup steps render via the shared
//  PlayoffMatchupRow (MatchCard anatomy) so they read like every other game in the app.
//  Multiple followed teams stack; if two could still meet, a storyline card says so. An
//  eliminated team keeps its section (muted).
//

import SwiftUI

struct PlayoffPathView: View {
    let bracket: PlayoffBracket
    let onOpenMatch: (String) -> Void

    @Environment(ClubStore.self) private var clubs
    @Environment(FollowingStore.self) private var following

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            let teams = followedTeams
            if teams.isEmpty {
                emptyState
            } else {
                ForEach(teams, id: \.self) { teamSection($0) }
                ForEach(storylines(teams), id: \.text) { storylineCard($0.text) }
            }
        }
        .padding(.horizontal, DS.pagePadding)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    // MARK: One team's road

    @ViewBuilder
    private func teamSection(_ abbr: String) -> some View {
        let accent = color(abbr)
        let elimRound = bracket.eliminationRound(abbr)
        VStack(alignment: .leading, spacing: 0) {
            hero(abbr, accent: accent, elimRound: elimRound)
            timeline(abbr, accent: accent)
        }
    }

    private func hero(_ abbr: String, accent: Color, elimRound: PlayoffRound?) -> some View {
        let club = clubs.club(forAbbreviation: abbr)
        let seed = bracket.seeds[abbr]
        return HStack(spacing: 12) {
            TeamLogo(urlString: club?.logoURL, teamAbbreviation: abbr, size: 60)
            VStack(alignment: .leading, spacing: 3) {
                if let seed {
                    Text("#\(seed) SEED").trackedCaps(color: accent)
                }
                if let elimRound {
                    Text("Eliminated in the \(elimRound.singular)")
                        .dsFont(17, weight: .heavy).foregroundStyle(Color.dsFgSecondary)
                } else {
                    Text("Your Road to the Championship")
                        .dsFont(17, weight: .heavy).foregroundStyle(Color.dsFgPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [accent.opacity(elimRound == nil ? 0.28 : 0.12), Color.dsBgCard],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous).strokeBorder(accent.opacity(0.2)))
        .padding(.bottom, 18)
    }

    // MARK: Timeline (nodes + connecting line + steps)

    @ViewBuilder
    private func timeline(_ abbr: String, accent: Color) -> some View {
        if let steps = bracket.path(forAbbreviation: abbr) {
            ZStack(alignment: .topLeading) {
                // Continuous accent line down the left.
                LinearGradient(colors: [accent, accent.opacity(0.25)], startPoint: .top, endPoint: .bottom)
                    .frame(width: 2)
                    .padding(.leading, 6).padding(.top, 6).padding(.bottom, 30)
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(steps) { stepRow($0, accent: accent) }
                    championRow(championAbbr: bracket.championship?.winnerAbbreviation)
                }
            }
        }
    }

    private func stepRow(_ step: PlayoffPathStep, accent: Color) -> some View {
        let nodeFilled = step.progress == .current || step.progress == .done
        let labelColor: Color = step.progress == .current ? .dsStateKickoff : .dsFgTertiary
        return HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(nodeFilled ? accent : Color.dsBgTertiary)
                .frame(width: 14, height: 14)
                .overlay(Circle().strokeBorder(nodeFilled ? accent : Color.dsFgTertiary, lineWidth: 2))
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 8) {
                Text(step.round.title).trackedCaps(size: 11, tracking: 1, color: labelColor)
                stepCard(step)
                if let win = step.winContext {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("Win →").dsFont(13, weight: .heavy).foregroundStyle(accent)
                        Text(humanize(win)).dsFont(13).foregroundStyle(Color.dsFgSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// The step's card: the shared MatchCard-anatomy row if the team is placed this round, else
    /// a dashed "to be decided" placeholder (the prior step's Win→ line names the opponent).
    @ViewBuilder
    private func stepCard(_ step: PlayoffPathStep) -> some View {
        if let m = step.matchup, m.isResolved {
            matchupRow(m)
        } else {
            HStack(spacing: 6) {
                Text(step.round.slug == PlayoffRound.championship.slug ? "NWSL Championship" : "Opponent to be decided")
                    .dsFont(13, weight: .semibold).foregroundStyle(Color.dsFgSecondary)
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: DS.radiusLg, style: .continuous).fill(Color.dsBgCard))
            .overlay(RoundedRectangle(cornerRadius: DS.radiusLg, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4])).foregroundStyle(Color.dsFgQuaternary))
        }
    }

    @ViewBuilder
    private func matchupRow(_ m: PlayoffMatchup) -> some View {
        let row = PlayoffMatchupRow(
            matchup: m,
            homeClub: m.home.abbreviation.flatMap { clubs.club(forAbbreviation: $0) },
            awayClub: m.away.abbreviation.flatMap { clubs.club(forAbbreviation: $0) },
            followedAbbreviations: followedAbbrs
        )
        if let id = m.eventID {
            Button { onOpenMatch(id) } label: { row }.buttonStyle(.plain)
        } else {
            row
        }
    }

    private func championRow(championAbbr: String?) -> some View {
        HStack(spacing: 12) {
            Circle().fill(Color.dsBgTertiary).frame(width: 16, height: 16)
                .overlay(Text("🏆").dsFont(10))
                .overlay(Circle().strokeBorder(Color.dsFgQuaternary, lineWidth: 2))
            if let championAbbr {
                // Mixed case deliberately (club name stays proper-case, not shouted).
                Text("\(clubs.club(forAbbreviation: championAbbr)?.displayName ?? championAbbr) — NWSL CHAMPION")
                    .dsFont(12, weight: .bold).tracking(0.4)
                    .foregroundStyle(color(championAbbr))
            } else {
                Text("NWSL CHAMPION").trackedCaps(size: 12, tracking: 0.8, color: .dsFgTertiary)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Storyline (two followed teams)

    private func storylineCard(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles").dsFont(16).foregroundStyle(Color.dsGameBracket)
            Text(humanize(text)).dsFont(13, weight: .medium).foregroundStyle(Color.dsFgPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.dsGameBracket.opacity(0.10), in: RoundedRectangle(cornerRadius: DS.radiusLg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusLg, style: .continuous).strokeBorder(Color.dsGameBracket.opacity(0.3)))
    }

    private func storylines(_ teams: [String]) -> [(round: PlayoffRound, text: String)] {
        var out: [(PlayoffRound, String)] = []
        for i in 0..<teams.count {
            for j in (i+1)..<teams.count {
                if let s = bracket.storyline(between: teams[i], and: teams[j]) { out.append(s) }
            }
        }
        return out
    }

    // MARK: Empty / helpers

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "flag.checkered").dsFont(34).foregroundStyle(Color.dsFgTertiary)
            Text("None of your teams are in the playoffs").dsFont(16, weight: .semibold).foregroundStyle(Color.dsFgPrimary)
            Text("Check the Bracket tab to follow the whole postseason.")
                .dsFont(13).foregroundStyle(Color.dsFgSecondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.top, 60).padding(.horizontal, 32)
    }

    /// Followed teams that are in the bracket, ordered by seed (best first).
    private var followedTeams: [String] {
        bracket.seeds.keys
            .filter { abbr in clubs.club(forAbbreviation: abbr).map { following.isFollowing($0) } ?? false }
            .sorted { (bracket.seeds[$0] ?? 99) < (bracket.seeds[$1] ?? 99) }
    }

    private var followedAbbrs: Set<String> { Set(followedTeams) }

    /// Team color per the match-surface convention (the shared `Color.teamColor` resolver:
    /// DesignTeamColors, dark-adjusted, neutral-gray fallback — was `.dsAccent`, now aligned
    /// with the other match surfaces).
    private func color(_ abbr: String) -> Color {
        Color.teamColor(for: abbr)
    }

    private func humanize(_ phrase: String) -> String {
        var out = phrase
        for abbr in bracket.seeds.keys {
            guard let name = clubs.club(forAbbreviation: abbr)?.displayName else { continue }
            out = out.replacingOccurrences(of: " \(abbr) ", with: " \(name) ")
            if out.hasSuffix(" \(abbr)") { out = String(out.dropLast(abbr.count)) + name }
            out = out.replacingOccurrences(of: "\(abbr) and ", with: "\(name) and ")
            out = out.replacingOccurrences(of: "and \(abbr) ", with: "and \(name) ")
        }
        return out
    }
}
