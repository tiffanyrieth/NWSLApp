//
//  BracketService.swift
//  NWSLApp
//
//  The Bracket Battle data client (Fan Zone game 2, 0.3.9). The boundary between
//  the game UI and the real backend: the global edition + matchups + the COMMUNITY
//  vote tally + the cross-user leaderboard live in Supabase (stateful/global), and
//  the user writes their own votes there (RLS-scoped, like FollowSyncService).
//
//  Offline-first, exactly like ContentService: every read falls back to the
//  BracketEditionProvider sample so the game renders without a network round-trip.
//
//  ⚠️ TEMP (Supabase wiring): the live Supabase reads/writes are the next step in
//  the 0.3.9 Bracket work (schema is checked in at supabase/schema.sql). Until they
//  land, the methods return the offline sample so the 5-screen UI is fully
//  exercisable in-sim. The SHIPPED game votes on real Supabase data — these samples
//  are dev/offline only. When wired: read `bracket_editions`/`bracket_matchups`,
//  write `bracket_votes`, read the `bracket_leaderboard` view.
//

import Foundation

/// One row of the (eventually Supabase-backed) standings.
struct BracketLeaderboardRow: Identifiable, Equatable {
    let rank: Int
    let name: String
    let points: Int
    let isYou: Bool
    var id: String { "\(rank)-\(name)" }
}

struct BracketService {
    /// The active edition + its matchups. Returns nil only when there is genuinely
    /// no active/upcoming edition (the Fan Zone gate hides the game) — never on a
    /// transient failure, where the offline sample stands in.
    func currentEdition() async -> BracketEdition? {
        // TEMP: live edition comes from Supabase (deferred); offline sample for now.
        BracketEditionProvider.sampleEdition()
    }

    /// Persist the user's submitted picks for a round (one row per matchup).
    func submit(editionID: String, round: BracketRound, picks: [String: String]) async {
        // TEMP: write each pick to `bracket_votes` (RLS owner-scoped) via SupabaseManager.
    }

    /// The matchups for a round, resolved with the real tally once it has closed.
    func results(editionID: String, round: BracketRound) async -> [BracketMatchup] {
        // TEMP: read `bracket_matchups` + the aggregated tally from Supabase.
        []
    }

    /// The standings with the signed-in user spliced in and ranked.
    func leaderboard(myPoints: Int) async -> [BracketLeaderboardRow] {
        // TEMP: real board = the `bracket_leaderboard` Supabase view.
        var rows = BracketEditionProvider.sampleLeaderboard()
            .map { (name: $0.name, points: $0.points, isYou: false) }
        rows.append((name: "You", points: myPoints, isYou: true))
        rows.sort { $0.points != $1.points ? $0.points > $1.points : ($0.isYou && !$1.isYou) }
        return rows.enumerated().map { i, r in
            BracketLeaderboardRow(rank: i + 1, name: r.name, points: r.points, isYou: r.isYou)
        }
    }
}
