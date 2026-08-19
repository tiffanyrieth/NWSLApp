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

    // MARK: - Superfan accuracy backing (0–100 economy)

    /// The accuracy DENOMINATOR for the Superfan economy: matchups across every TALLIED (resolved) round
    /// of an edition — the rounds BEFORE the currently-open one in play order. Missed rounds are INCLUDED.
    /// This is the behavior fix for the "100% accuracy with 4 points" bug — a player who skipped rounds
    /// gets those rounds' matchups counted as zeros in the denominator, not excluded. `currentRoundRaw` is
    /// a `BracketRound` raw value; `poolSize` is the edition's entrant count.
    static func talliedMatchupDenominator(poolSize: Int, currentRoundRaw: Int) -> Int {
        guard let current = BracketRound(rawValue: currentRoundRaw) else { return 0 }
        return BracketRound.rounds(forEntrants: poolSize)
            .filter { $0 < current }
            .reduce(0) { $0 + $1.matchupCount }
    }

    /// Correct picks banked across an edition, recovered from the per-round POINTS the store holds
    /// (points = correct × round.points ⇒ correct = points / round.points). Rounds the user skipped are
    /// simply absent ⇒ contribute 0 correct — the "missed = zero" numerator that pairs with the
    /// structure denominator above.
    static func correctPicks(fromRoundScores roundScores: [Int: Int]) -> Int {
        roundScores.reduce(0) { sum, entry in
            guard let round = BracketRound(rawValue: entry.key), round.points > 0 else { return sum }
            return sum + entry.value / round.points
        }
    }

    // MARK: - Result-card verdict copy

    /// The user's outcome on a resolved matchup, for the one-line result verdict.
    enum VerdictOutcome { case correct, missed, satOut }

    /// The one-line verdict under a result card: a margin word (Runaway / Comfortable / Solid /
    /// Nail-biter) describing how decisively the community advanced the winner, plus the winner's action.
    /// ⚠️ The leading margin ADJECTIVE is praise-adjacent, so it appears only on a CORRECT call (earned)
    /// or a SAT-OUT matchup (neutral) — NEVER on a MISS, where "Solid — … took it" in red read as praise
    /// for a pick you got wrong (owner-caught 2026-08-04). A miss shows the winner's ACTION alone; the
    /// action verb still carries the margin, and the exact split lives only in the "See how the league
    /// voted" donut (no inline percentages — this stays a scannable quick-read that never repeats the donut).
    static func verdictText(winnerPercent: Int, winnerName: String, roundPoints: Int,
                            outcome: VerdictOutcome) -> String {
        let adjective: String
        let action: String
        switch winnerPercent {
        case 90...:    adjective = "Runaway";     action = "\(winnerName) dominated"
        case 70..<90:  adjective = "Comfortable"; action = "\(winnerName) cruised through"
        case 55..<70:  adjective = "Solid";       action = "\(winnerName) took it"
        default:       adjective = "Nail-biter";  action = "\(winnerName) barely survived"
        }
        switch outcome {
        case .correct: return "\(adjective): \(action)  ·  +\(roundPoints) pts"
        case .missed:  return action
        case .satOut:  return "\(adjective): \(action)"
        }
    }
}
