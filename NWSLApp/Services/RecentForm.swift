//
//  RecentForm.swift
//  NWSLApp
//
//  Pure, stateless derivation of each club's recent W/D/L form from the season
//  scoreboard. ESPN's standings endpoint carries only cumulative totals (no
//  recent-results sequence), so the Standings "Last 5" column is computed here
//  from completed matches in the shared `MatchStore`.
//
//  The W/D/L classification mirrors `MatchDetailViewModel.form(for:in:)` (the
//  future-match preview). That duplication is deliberate and temporary: this
//  redesign lands one screen at a time, and the two will be unified when the
//  Match Detail screen is reworked (its file is intentionally untouched here).
//  Reuses the shared top-level `MatchResult` enum.
//

import Foundation

enum RecentForm {

    /// Last-5 results for every club that appears in the season, keyed by team
    /// abbreviation (the same join key `MatchStore` uses), **oldest → newest**.
    ///
    /// One pass over the season: each completed match contributes a result to
    /// BOTH teams, then we keep the trailing five per team. O(events) — not
    /// O(events × teams) — so it's cheap to recompute on a view refresh.
    static func lastFiveByAbbreviation(in season: [Event]) -> [String: [MatchResult]] {
        // Chronological so appended results read oldest → newest.
        let finals = season
            .filter { $0.statusState == "post" }
            .sorted { ($0.kickoff ?? .distantPast) < ($1.kickoff ?? .distantPast) }

        var byTeam: [String: [MatchResult]] = [:]
        for game in finals {
            guard let homeAbbr = game.homeCompetitor?.team?.abbreviation,
                  let awayAbbr = game.awayCompetitor?.team?.abbreviation,
                  let homeScore = game.homeCompetitor?.score.flatMap(Int.init),
                  let awayScore = game.awayCompetitor?.score.flatMap(Int.init) else { continue }

            byTeam[homeAbbr, default: []].append(result(scored: homeScore, conceded: awayScore))
            byTeam[awayAbbr, default: []].append(result(scored: awayScore, conceded: homeScore))
        }
        return byTeam.mapValues { Array($0.suffix(5)) }
    }

    /// Last-5 results for a single club (abbreviation join), oldest → newest.
    static func lastFive(forAbbreviation abbreviation: String, in season: [Event]) -> [MatchResult] {
        lastFiveByAbbreviation(in: season)[abbreviation] ?? []
    }

    private static func result(scored: Int, conceded: Int) -> MatchResult {
        scored > conceded ? .win : (scored == conceded ? .draw : .loss)
    }
}
