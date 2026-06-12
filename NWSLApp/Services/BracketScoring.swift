//
//  BracketScoring.swift
//  NWSLApp
//
//  The Bracket Battle scorer — Fan Zone game 2 (0.3.9). Pure functions, no state or
//  I/O, so every rule is unit-testable (BracketScoringTests) and the view model just
//  calls them once a round's real community tally lands. You score by predicting
//  which entrant the COMMUNITY advances; each correct pick is worth that round's
//  escalating value (Rd of 64 +5 … Final +40 — see BracketRound.points).
//
//  NOTE on the maximum: the per-round values × matchup counts (32·5 + 16·8 + 8·12 +
//  4·18 + 2·25 + 1·40) sum to 546 for a perfect 64-pool bracket — NOT the 468 the
//  design mock printed (an arithmetic slip in the prototype). We derive the max from
//  the rule via `maxPoints(...)` so the "perfect bracket" figure is always
//  self-consistent with the scoring; flagged to the owner.
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
