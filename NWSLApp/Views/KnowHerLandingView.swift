//
//  KnowHerLandingView.swift
//  NWSLApp
//
//  Know Her Game — the LANDING PAGE (Fan Zone v2 redesign; owner terminology 2026-07-21). Every entry to
//  Know Her Game lands here first, single-team fan or many. It's a small hub, not just a team selector,
//  with three persistent sections:
//    • This round   — a row per followed team: an available player (tap to play / re-open results), or an
//                     EXHAUSTED team (dimmed, "All eligible players featured"). When EVERY followed team
//                     is exhausted this in-season round, the section is replaced by an "All caught up" state.
//    • Last round   — the previous edition's results per team, tappable to re-open the community recap
//                     (fixes the old bug where a multi-team fan couldn't revisit a completed round).
//    • How players are chosen — the selection rules (starters → 100+ minutes → no repeats), so the system
//                     reads as fair and intentional.
//  Editions are BIWEEKLY and numbered ("Round N", proxy-stamped) — Know Her Game as a season of rounds.
//
//  Reachable in-season even when the user's teams are exhausted (HomeView.knowHerVisible = hasCurrentRound
//  || hasPreviousWeek), so the honest "all caught up" state shows instead of the card silently vanishing.
//  The pool + played state live in the shared KnowHerGameStore; team names resolve via ClubStore.
//

import SwiftUI

struct KnowHerLandingView: View {
    /// The followed-team abbreviations (Home computes them for the gate too), so the landing page
    /// can (re)load the pool if reached before Home warmed it.
    let teams: [String]

    @Environment(KnowHerGameStore.self) private var store
    @Environment(ClubStore.self) private var clubs

    /// Which player the result sheet is showing + from which round. `.current` opens the game (or its
    /// result recap if already played); `.lastRound` always opens a read-only review of a closed edition.
    private enum ActiveEntry: Identifiable {
        case current(KnowHerPlayer)
        case lastRound(KnowHerPlayer)
        var id: String {
            switch self {
            case .current(let p): return "cur-\(p.id)"
            case .lastRound(let p): return "prev-\(p.id)"
            }
        }
    }

    @State private var activeEntry: ActiveEntry?
    @State private var pendingPlayer: KnowHerPlayer?
    @State private var gateRequested = false

    private let accent = Color.dsGameSpotlight

    /// The three rules shown in "How players are chosen" — plain-English mirror of the proxy's
    /// `rankEligible` gate (starters always eligible; 100' floor for non-starters; no repeats per season).
    private let selectionRules = [
        "Players who have started matches are featured first",
        "Then players with 100+ minutes on the pitch this season",
        "Each player is only featured once per season — no repeats",
    ]

    var body: some View {
        Group {
            switch store.loadState {
            case .idle, .loading:
                ProgressView("Loading this round's players…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .error(let message):
                errorView(message)
            case .loaded:
                loadedContent
            }
        }
        .nativeBackButton(title: "Know Her Game")
        .background(Color.dsBgGrouped)
        .task {
            GameCenterManager.shared.authenticate()
            await store.loadIfNeeded(teams: teams)
        }
        .sheet(item: $activeEntry) { entry in
            NavigationStack {
                switch entry {
                case .current(let player):
                    // Already played → read-only recap; not yet → play it. (The gate has already run
                    // for an unplayed tap, so the user is signed in either way.)
                    KnowHerGameView(player: player, weekKey: store.weekKey ?? "",
                                    entry: store.isPlayed(player) ? .review : .play) { next in
                        activeEntry = .current(next)   // "Next player ›" swaps to another team's player
                    }
                case .lastRound(let player):
                    // Closed edition — review-only (final community numbers, your score if you played).
                    KnowHerGameView(player: player, weekKey: store.previousWeekKey ?? "", entry: .review)
                }
            }
        }
        .fanZoneGate(isRequested: $gateRequested, gameName: "Know Her Game", accent: accent) {
            if let pendingPlayer { activeEntry = .current(pendingPlayer) }
        }
    }

    private var loadedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                let available = store.players
                let exhausted = exhaustedTeams()

                if available.isEmpty && !exhausted.isEmpty {
                    allCaughtUp(exhausted: exhausted)          // Cases 3 & 4: every followed team exhausted
                } else {
                    thisRoundSection(available: available, exhausted: exhausted)  // Cases 1 & 2
                }

                if store.hasPreviousWeek {
                    lastRoundSection()
                }

                howPlayersAreChosen()

                Text("A new round every two weeks.")
                    .dsFont(11).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
            .fanZonePlayingAsHeader(accent: accent)
        }
    }

    // MARK: - Data helpers

    /// Followed teams with NO featured player this round — but only when a round is actually live
    /// (`hasCurrentRound`), so we never claim "exhausted" in the offseason / before load.
    private func exhaustedTeams() -> [String] {
        guard store.hasCurrentRound else { return [] }
        let available = Set(store.players.map { $0.teamAbbreviation.uppercased() })
        return teams.map { $0.uppercased() }.filter { !available.contains($0) }
    }

    private func teamName(_ abbr: String) -> String {
        clubs.club(forAbbreviation: abbr)?.displayName ?? abbr
    }

    // MARK: - This round

    @ViewBuilder
    private func thisRoundSection(available: [KnowHerPlayer], exhausted: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionEyebrow("This round", round: store.round)
            ForEach(available) { player in playerRow(player) }
            ForEach(exhausted, id: \.self) { abbr in exhaustedRow(abbr) }
            if !exhausted.isEmpty {
                Text("Teams marked \u{201C}all eligible players featured\u{201D} return when a new player crosses 100 minutes or earns their first start.")
                    .dsFont(12).foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.dsBgTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func playerRow(_ player: KnowHerPlayer) -> some View {
        let played = store.isPlayed(player)
        let teamColor = Color.teamColor(for: player.teamAbbreviation, liftOnDark: false, fallback: accent)
        return Button {
            if played {
                activeEntry = .current(player)   // straight to the result recap (already signed in)
            } else {
                pendingPlayer = player
                gateRequested = true             // sign-in gate for a first play
            }
        } label: {
            HStack(spacing: 14) {
                KnowHerPlayerAvatar(player: player, ring: teamColor, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(player.playerName).dsFont(17, weight: .semibold).foregroundStyle(.primary)
                    Text(played ? "\(player.position) · \(player.teamAbbreviation.uppercased())"
                                : "New player available")
                        .dsFont(15).foregroundStyle(played ? AnyShapeStyle(.secondary) : AnyShapeStyle(accent))
                }
                Spacer()
                if played, let score = store.score(for: player) {
                    resultsBadge(score: score, total: player.questions.count)
                } else {
                    HStack(spacing: 3) {
                        Text("Play").dsFont(15, weight: .semibold)
                        Image(systemName: "chevron.right").dsFont(11, weight: .bold)
                    }
                    .foregroundStyle(accent)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.dsBgCard)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)   // completed rows stay tappable → revisit results (opens .review, no replay)
    }

    /// A followed team that has used all its eligible players this season — dimmed, non-tappable.
    private func exhaustedRow(_ abbr: String) -> some View {
        let teamColor = Color.teamColor(for: abbr, liftOnDark: false, fallback: accent)
        return HStack(spacing: 14) {
            teamMonogram(abbr, color: teamColor, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(teamName(abbr)).dsFont(17, weight: .semibold).foregroundStyle(.primary)
                Text("All eligible players featured").dsFont(15).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsBgCard)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .opacity(0.55)
    }

    /// Completed-row affordance: the score in amber + a "Results ›" cue (a completed row is a doorway to
    /// the live community results, not a dead end).
    private func resultsBadge(score: Int, total: Int) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text("\(score)/\(total)").dsFont(15, weight: .bold).foregroundStyle(accent)
            HStack(spacing: 2) {
                Text("Results").dsFont(11, weight: .semibold)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - All caught up (every followed team exhausted)

    @ViewBuilder
    private func allCaughtUp(exhausted: [String]) -> some View {
        VStack(spacing: 12) {
            if exhausted.count == 1 {
                let abbr = exhausted[0]
                teamMonogram(abbr, color: Color.teamColor(for: abbr, liftOnDark: false, fallback: accent), size: 56)
                Text("All caught up for \(teamName(abbr))")
                    .dsFont(18, weight: .bold).multilineTextAlignment(.center)
                Text("Every eligible \(teamName(abbr)) player has been featured this season. If a returning or breakout player crosses 100 minutes or earns a start, she'll show up here.")
                    .dsFont(13).foregroundStyle(.secondary).multilineTextAlignment(.center)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44)).foregroundStyle(accent)
                Text("All caught up").dsFont(18, weight: .bold)
                Text("Every eligible player on your followed teams has been featured this season. If a returning or breakout player crosses 100 minutes or earns a start, she'll appear here.")
                    .dsFont(13).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }

    // MARK: - Last round (review the previous edition's community results)

    private func lastRoundSection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionEyebrow("Last round", round: store.previousRound)
            ForEach(store.previousPlayers) { player in lastRoundRow(player) }
            Text("Community results stay for one round after each edition closes.")
                .dsFont(11).foregroundStyle(.tertiary)
        }
    }

    private func lastRoundRow(_ player: KnowHerPlayer) -> some View {
        let editionKey = player.editionKey(weekKey: store.previousWeekKey ?? "")
        let score = store.score(editionKey: editionKey)
        let teamColor = Color.teamColor(for: player.teamAbbreviation, liftOnDark: false, fallback: accent)
        return Button {
            activeEntry = .lastRound(player)
        } label: {
            HStack(spacing: 12) {
                KnowHerPlayerAvatar(player: player, ring: teamColor.opacity(0.6), size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.playerName).dsFont(15, weight: .semibold).foregroundStyle(.secondary)
                    Text("\(player.position) · \(player.teamAbbreviation.uppercased())")
                        .dsFont(12).foregroundStyle(.tertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if let score {
                        Text("\(score)/\(player.questions.count)")
                            .dsFont(12, weight: .bold).foregroundStyle(accent.opacity(0.75))
                    }
                    HStack(spacing: 2) {
                        Text("Results").dsFont(11, weight: .semibold)
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(.tertiary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.dsBgCard)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - How players are chosen

    private func howPlayersAreChosen() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("HOW PLAYERS ARE CHOSEN")
                .dsFont(11, weight: .bold).tracking(0.8).foregroundStyle(accent)
            ForEach(Array(selectionRules.enumerated()), id: \.offset) { index, rule in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .dsFont(11, weight: .bold).foregroundStyle(accent)
                        .frame(width: 20, height: 20)
                        .background(accent.opacity(0.15), in: Circle())
                    Text(rule).dsFont(13).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsBgCard)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Shared bits

    private func sectionEyebrow(_ title: String, round: Int?) -> some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .dsFont(11, weight: .bold).tracking(0.8).foregroundStyle(.secondary)
            if let round {
                Text("Round \(round)")
                    .dsFont(11, weight: .bold).tracking(0.4).foregroundStyle(accent)
            }
            Spacer()
        }
    }

    /// A team-color monogram for a team with no player row (exhausted). Players use `KnowHerPlayerAvatar`
    /// (headshots); a team with no featured player has no headshot, so we show its abbreviation.
    private func teamMonogram(_ abbr: String, color: Color, size: CGFloat) -> some View {
        Circle().fill(color.opacity(0.22))
            .frame(width: size, height: size)
            .overlay(
                Text(abbr.uppercased())
                    .font(.system(size: size * 0.32, weight: .bold))
                    .foregroundStyle(color)
            )
    }

    private func errorView(_ message: String) -> some View {
        RetryStateView(message: message) { await store.loadIfNeeded(teams: teams, force: true) }
    }
}
