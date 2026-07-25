//
//  SuperfanScoring.swift
//  NWSLApp
//
//  The Superfan 0–100 economy (Fan Zone Competitive Redesign, PR1). PURE math, deliberately free of
//  SwiftUI/GameKit so every rule is unit-testable in isolation (SuperfanScoringTests) — the same stance
//  as GameCenterScores. Replaces the old additive `superfanTotal` (trivia correct + predict points +
//  bracket points + know-her points, mismatched units) with a normalized score: each of the four games
//  contributes `accuracy × 25`, summed to 0–100.
//
//  Source of truth = per-game CORRECT/ATTEMPTED counts (SuperfanCounts). Accuracy and contribution are
//  DERIVED, never stored as truth — because accuracy legitimately falls (a bad game lowers it) while the
//  counts only grow. That growth is what makes the score reinstall-safe: `SuperfanCounts.merged(with:)`
//  takes the GREATEST of each count, so a wiped device can't lower the server total, yet an accuracy that
//  should drop still drops. (Old `max(total)` clamped the wrong thing.)
//

import Foundation

/// The four Fan Zone games that feed Superfan. Pure — display color/symbol live in the view layer.
enum SuperfanGame: String, CaseIterable, Identifiable {
    case predict, bracket, khg, trivia
    var id: String { rawValue }

    /// Each game contributes at most this to the 0–100 total (four games × 25 = 100).
    static let maxContribution: Double = 25
}

/// The durable per-game count ledger — one value set per (user, season), mirrored 1:1 to
/// `superfan_scores` columns. These are the SOURCE OF TRUTH; accuracy/contribution/total derive from them.
struct SuperfanCounts: Equatable, Codable {
    var predictCorrect = 0
    var predictTotal   = 0   // 11 × scored matches
    var bracketCorrect = 0
    var bracketTotal   = 0   // edition-structure matchups over tallied rounds (missed rounds = zeros)
    var khgCorrect     = 0
    var khgTotal       = 0
    var triviaCorrect  = 0
    var triviaTotal    = 0
    var triviaStreak   = 0   // consecutive Trivia rounds — drives the +1/round (cap +10) bonus

    static let zero = SuperfanCounts()

    /// Correct/attempted for one game (streak handled separately).
    func pair(for game: SuperfanGame) -> (correct: Int, total: Int) {
        switch game {
        case .predict: return (predictCorrect, predictTotal)
        case .bracket: return (bracketCorrect, bracketTotal)
        case .khg:     return (khgCorrect, khgTotal)
        case .trivia:  return (triviaCorrect, triviaTotal)
        }
    }

    /// Reinstall-safe merge: the GREATEST of every count (they only ever grow), and the higher streak.
    /// This is what `SuperfanService.submit` reconciles local vs server with — a fresh install can't
    /// lower the server, but a genuinely-changed accuracy still recomputes from the merged counts.
    func merged(with other: SuperfanCounts) -> SuperfanCounts {
        SuperfanCounts(
            predictCorrect: max(predictCorrect, other.predictCorrect),
            predictTotal:   max(predictTotal, other.predictTotal),
            bracketCorrect: max(bracketCorrect, other.bracketCorrect),
            bracketTotal:   max(bracketTotal, other.bracketTotal),
            khgCorrect:     max(khgCorrect, other.khgCorrect),
            khgTotal:       max(khgTotal, other.khgTotal),
            triviaCorrect:  max(triviaCorrect, other.triviaCorrect),
            triviaTotal:    max(triviaTotal, other.triviaTotal),
            triviaStreak:   max(triviaStreak, other.triviaStreak)
        )
    }

    /// How many of the four games have contributed at all (≥1 attempt) — the `games_played` gate value.
    /// A game contributes from attempt #1 (owner ruling 2026-07-22: no unlock gate, no minimum).
    var gamesPlayed: Int {
        SuperfanGame.allCases.filter { pair(for: $0).total > 0 }.count
    }
}

/// A computed snapshot for the detail screen + carousel card: each game's 0–25 contribution and the
/// 0–100 total. `accuracy(for:)` is defined as contribution/25 so the displayed % and the bar always
/// agree — for Predict/Bracket/KHG that's the raw accuracy; for Trivia it's the streak-bonused effective
/// accuracy, so the "34%" the row shows and the "8.5 / 25" bar can never disagree.
struct SuperfanBreakdown: Equatable {
    let contributions: [SuperfanGame: Double]   // 0…25 each
    let total: Int                              // 0…100

    func contribution(for game: SuperfanGame) -> Double { contributions[game] ?? 0 }

    /// Displayed accuracy 0…1 (== contribution / 25), so the % label and the progress bar stay locked.
    func accuracy(for game: SuperfanGame) -> Double {
        contribution(for: game) / SuperfanGame.maxContribution
    }
}

enum SuperfanScoring {
    /// Raw accuracy 0…1 for a game (0 when nothing attempted). No streak bonus.
    static func accuracy(for game: SuperfanGame, counts: SuperfanCounts) -> Double {
        let (correct, total) = counts.pair(for: game)
        return total > 0 ? Double(correct) / Double(total) : 0
    }

    /// A game's 0–25 contribution. Predict/Bracket/KHG = accuracy × 25. Trivia = (accuracy + streak
    /// bonus) × 25, where the bonus is +1 percentage-point per consecutive round, capped at +10, and the
    /// effective accuracy is capped at 1.0 so contribution never exceeds 25.
    static func contribution(for game: SuperfanGame, counts: SuperfanCounts) -> Double {
        let base = accuracy(for: game, counts: counts)
        let withBonus: Double
        if game == .trivia {
            let bonus = Double(min(max(counts.triviaStreak, 0), 10)) / 100.0  // up to +0.10
            withBonus = base + bonus
        } else {
            withBonus = base
        }
        // Clamp effective accuracy to [0, 1] for EVERY game so a contribution can never exceed 25 — covers
        // the trivia streak bonus AND a transient bracket edge where a just-tallied current round could
        // briefly make correct picks exceed the structure denominator.
        let effective = min(1.0, max(0.0, withBonus))
        return effective * SuperfanGame.maxContribution
    }

    /// The 0–100 Superfan total = Σ of the four contributions, rounded, clamped.
    static func total(counts: SuperfanCounts) -> Int {
        let sum = SuperfanGame.allCases.reduce(0.0) { $0 + contribution(for: $1, counts: counts) }
        return min(100, max(0, Int(sum.rounded())))
    }

    /// The full breakdown for the UI in one pass.
    static func breakdown(counts: SuperfanCounts) -> SuperfanBreakdown {
        var contributions: [SuperfanGame: Double] = [:]
        for game in SuperfanGame.allCases {
            contributions[game] = contribution(for: game, counts: counts)
        }
        return SuperfanBreakdown(contributions: contributions, total: total(counts: counts))
    }
}
