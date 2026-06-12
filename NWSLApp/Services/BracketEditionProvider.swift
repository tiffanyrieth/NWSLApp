//
//  BracketEditionProvider.swift
//  NWSLApp
//
//  ⚠️ TEMP / OFFLINE-FIRST FALLBACK. The LIVE Bracket Battle edition + its real
//  community vote tally come from Supabase (BracketService). This provider builds a
//  single sample edition so the game renders in previews, in the simulator, and
//  offline — exactly the role the other seed providers (FeedContentProvider,
//  TeamContentProvider, PlayerSpotlightProvider) play. The players are real NWSL
//  forwards (the set the Claude Design reference used); the vote splits here are
//  illustrative sample data — the SHIPPED game scores on real Supabase votes, never
//  these. Retire / shrink once the proxy edition-generator (deferred) is live.
//

import Foundation

enum BracketEditionProvider {

    /// (name, jersey, team) — a compact real-forward pool for the offline sample.
    private static let pool: [(String, Int, String)] = [
        ("Rodman", 2, "WAS"), ("Banda", 9, "ORL"), ("Chawinga", 17, "KC"), ("Swanson", 7, "CHI"),
        ("Hatch", 11, "WAS"), ("Marta", 10, "ORL"), ("Shaw", 12, "NJ"), ("Macario", 28, "SD"),
        ("Thompson", 7, "LA"), ("Sanchez", 8, "NC"), ("Wilson", 19, "POR"), ("Moultrie", 13, "POR"),
        ("Bethune", 6, "KC"), ("LaBonta", 15, "KC"), ("Fox", 3, "NC"), ("Bugg", 14, "DEN"),
    ]

    /// A 16-forward "Top Forward" sample edition with Round of 16 open for voting.
    /// (Live editions are 64; the model supports any power-of-two pool, so the
    /// offline sample is intentionally small + hand-real.)
    static func sampleEdition(now: Date = Date()) -> BracketEdition {
        let id = "sample-top-forward-2026"
        let entrants = pool.enumerated().map { i, p in
            BracketEntrant(id: "s\(i)", playerName: p.0, jerseyNumber: p.1, teamAbbreviation: p.2)
        }
        let firstRound = BracketRound.rounds(forEntrants: entrants.count).first ?? .roundOf16
        // Standard-ish seeding: 1 v N, 2 v N-1, … so favourites don't collide early.
        let n = entrants.count
        let matchups = (0..<n / 2).map { slot in
            BracketMatchup(
                id: BracketMatchup.matchupID(editionID: id, round: firstRound, slot: slot),
                round: firstRound, slot: slot,
                entrantA: entrants[slot], entrantB: entrants[n - 1 - slot],
                communityWinnerID: nil, splitAPercent: nil
            )
        }
        return BracketEdition(
            id: id, themeLabel: "TOP FORWARD", title: "Best Forward · 2026", emoji: "⚽",
            type: .statsSeeded, entrants: entrants, currentRound: firstRound,
            roundOpenedAt: now.addingTimeInterval(-24 * 3600),
            roundClosesAt: now.addingTimeInterval(32 * 3600),
            fanCount: 4218, matchups: matchups
        )
    }

    /// Illustrative leaderboard opponents for the offline sample (the live board is a
    /// Supabase view). "You" is spliced in at runtime by the view model.
    static func sampleLeaderboard() -> [(name: String, points: Int)] {
        [("bracket_boss", 155), ("nwslfan_23", 150), ("goalqueen", 140),
         ("spirit_sarah", 115), ("thorns_til_death", 98), ("rookie_riley", 60)]
    }
}
