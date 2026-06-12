//
//  BracketScoring.swift
//  NWSLApp
//
//  The Bracket Battle scorer — Fan Zone game 2 (0.3.9). Pure functions, no state or
//  I/O, so every rule is unit-testable (BracketScoringTests) and the view model just
//  calls them once a round's real community tally lands. You score by predicting
//  which entrant the COMMUNITY advances; each correct pick is worth that round's
//  tiered value (1·1·2·2·3·3 by round — see BracketRound.points, v2).
//
//  NOTE on the maximum: the per-round values × matchup counts (32·1 + 16·1 + 8·2 +
//  4·2 + 2·3 + 1·3) sum to 81 for a perfect 64-pool bracket. We derive the max from
//  the rule via `maxPoints(...)` so the "perfect bracket" figure is always
//  self-consistent with the scoring.
//

import Foundation

enum BracketScoring {
    /// Points earned in one round: each pick that matches the community winner is
    /// worth `round.points`. Unresolved matchups (round not closed) and matchups the
    /// user didn't pick score nothing.
    static func roundPoints(picks: [String: String], matchups: [BracketMatchup]) -> Int {
        correctCount(picks: picks, matchups: matchups) * (matchups.first?.round.points ?? 0)
    }

    /// How many of the user's picks matched the community winner (for "N of M
    /// correct" copy).
    static func correctCount(picks: [String: String], matchups: [BracketMatchup]) -> Int {
        matchups.reduce(0) { count, m in
            guard let winner = m.communityWinnerID, let pick = picks[m.id], pick == winner
            else { return count }
            return count + 1
        }
    }

    /// The maximum a perfect bracket can score across an edition's rounds (every pick
    /// in every round correct). Derived from the rule, not hardcoded.
    static func maxPoints(rounds: [BracketRound]) -> Int {
        rounds.reduce(0) { $0 + $1.matchupCount * $1.points }
    }
}
