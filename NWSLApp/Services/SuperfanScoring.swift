//
//  SuperfanScoring.swift
//  NWSLApp
//
//  The Superfan 0–100 economy — REBUILT 2026-08-04 (owner: "blow it up"). PURE math, deliberately free of
//  SwiftUI/GameKit so every rule is unit-testable in isolation (SuperfanScoringTests).
//
//  Four game "channels", each 0–25, summed to 0–100. Within a channel:
//        contribution = accuracy × 20  +  engagement (0–5)
//  • ACCURACY (0–20): the raw per-game correct/attempted ratio × 20. Derived from the monotonic count
//    ledger (SuperfanCounts) — accuracy legitimately FALLS when you have a bad game, while the counts
//    only grow, which is what keeps the score reinstall-safe (`merged(with:)` = GREATEST of each count).
//  • ENGAGEMENT (0–5): a FORGIVING participation "momentum" (owner ruling — reward showing up, never a
//    reset-on-miss penalty). +1 each cycle you play, −1 for a cycle you miss, floored at 0, capped at 5.
//    The cadence-aware decay is computed by the store bridge (`SuperfanCounts+Stores`); this file just
//    reads the resulting momentum. Merged via `max` so a reinstall keeps your best (forgiving).
//
//  TIER-FLOOR LOCK: the DISPLAYED score never drops below a tier you've earned this season
//  (`displayScore = max(currentTotal, tierFloor(seasonPeak))`). The season peak is the existing
//  `season_history.peak_score`; no new storage.
//
//  ⚠️ EVERY economy constant lives here and is TUNABLE — storage holds only raw inputs, the score is
//  always derived, so the whole curve re-tunes with a code change and ZERO migration (owner: build +
//  tune live). Do not scatter these numbers into the views or the DB.
//

import Foundation

/// The four Fan Zone games that feed Superfan. Pure — display color/symbol live in the view layer.
enum SuperfanGame: String, CaseIterable, Identifiable {
    case predict, bracket, khg, trivia
    var id: String { rawValue }

    /// Each game contributes at most this to the 0–100 total (four games × 25 = 100).
    static let maxContribution: Double = SuperfanScoring.accuracyWeight + Double(SuperfanScoring.engagementMax)
}

/// The durable per-game ledger — one value set per (user, season), mirrored 1:1 to `superfan_scores`
/// columns. SOURCE OF TRUTH; accuracy/contribution/total derive from it.
struct SuperfanCounts: Equatable, Codable {
    var predictCorrect = 0
    var predictTotal   = 0   // 11 × scored matches
    var bracketCorrect = 0
    var bracketTotal   = 0   // edition-structure matchups over tallied rounds (missed rounds = zeros)
    var khgCorrect     = 0
    var khgTotal       = 0
    var triviaCorrect  = 0
    var triviaTotal    = 0

    /// FORGIVING engagement momentum per channel (0…5). Computed cadence-aware by the store bridge
    /// (+1 played cycle, −1 missed cycle, clamped). Stored + `max`-merged so a reinstall keeps your best.
    var predictMomentum = 0
    var bracketMomentum = 0
    var khgMomentum     = 0
    var triviaMomentum  = 0

    static let zero = SuperfanCounts()

    /// Correct/attempted for one game (momentum handled separately).
    func pair(for game: SuperfanGame) -> (correct: Int, total: Int) {
        switch game {
        case .predict: return (predictCorrect, predictTotal)
        case .bracket: return (bracketCorrect, bracketTotal)
        case .khg:     return (khgCorrect, khgTotal)
        case .trivia:  return (triviaCorrect, triviaTotal)
        }
    }

    /// This channel's forgiving engagement momentum (0…5).
    func momentum(for game: SuperfanGame) -> Int {
        switch game {
        case .predict: return predictMomentum
        case .bracket: return bracketMomentum
        case .khg:     return khgMomentum
        case .trivia:  return triviaMomentum
        }
    }

    /// Reinstall-safe merge: each game's `(correct, total)` is taken as an ATOMIC PAIR from the side
    /// with the greater `total` (via `LeaderboardRanking.fullerPair`), and momentum takes the higher
    /// side. A fresh install can't lower the server (its `total` is 0, so the server pair wins whole),
    /// and a genuinely-fuller device carries its correct+total together — so the merge can never pair a
    /// `correct` from one device with a `total` from the other and synthesize an accuracy neither
    /// produced (the old per-scalar `max` did exactly that: 8/22 vs 10/11 → 10/22). `total` stays
    /// monotonic, so reinstall-safety is preserved. Momentum is a standalone 0–5 engagement value (not a
    /// ratio partner), so keeping it on `max` — a reinstall keeps your best momentum — is correct.
    func merged(with other: SuperfanCounts) -> SuperfanCounts {
        func fuller(_ lc: Int, _ lt: Int, _ oc: Int, _ ot: Int) -> (Int, Int) {
            let r = LeaderboardRanking.fullerPair(local: (lc, lt), server: (oc, ot))
            return (r.num, r.den)
        }
        let p = fuller(predictCorrect, predictTotal, other.predictCorrect, other.predictTotal)
        let b = fuller(bracketCorrect, bracketTotal, other.bracketCorrect, other.bracketTotal)
        let k = fuller(khgCorrect, khgTotal, other.khgCorrect, other.khgTotal)
        let t = fuller(triviaCorrect, triviaTotal, other.triviaCorrect, other.triviaTotal)
        return SuperfanCounts(
            predictCorrect: p.0, predictTotal: p.1,
            bracketCorrect: b.0, bracketTotal: b.1,
            khgCorrect: k.0, khgTotal: k.1,
            triviaCorrect: t.0, triviaTotal: t.1,
            predictMomentum: max(predictMomentum, other.predictMomentum),
            bracketMomentum: max(bracketMomentum, other.bracketMomentum),
            khgMomentum:     max(khgMomentum, other.khgMomentum),
            triviaMomentum:  max(triviaMomentum, other.triviaMomentum)
        )
    }

    /// How many of the four games have contributed at all (≥1 attempt) — the `games_played` gate value.
    /// A game contributes from attempt #1 (owner ruling 2026-07-22: no unlock gate, no minimum).
    var gamesPlayed: Int {
        SuperfanGame.allCases.filter { pair(for: $0).total > 0 }.count
    }
}

/// A computed snapshot for the detail screen + carousel card: each channel's accuracy/engagement/total
/// split, and the 0–100 total. The detail view now shows accuracy AND engagement separately, so they're
/// broken out here rather than folded together.
struct SuperfanBreakdown: Equatable {
    struct Channel: Equatable {
        let accuracyPoints: Double    // 0…20
        let engagementPoints: Int     // 0…5
        var contribution: Double { min(SuperfanGame.maxContribution, accuracyPoints + Double(engagementPoints)) }
        /// Displayed accuracy 0…1 (the ratio, for the "%" label).
        let accuracyRatio: Double
    }
    let channels: [SuperfanGame: Channel]
    let total: Int                   // 0…100 (raw, before the tier-floor lock)

    func channel(for game: SuperfanGame) -> Channel {
        channels[game] ?? Channel(accuracyPoints: 0, engagementPoints: 0, accuracyRatio: 0)
    }
    func contribution(for game: SuperfanGame) -> Double { channel(for: game).contribution }
}

enum SuperfanScoring {

    // MARK: - Tunable economy constants (ALL of them — see the file header)

    /// Max ACCURACY points per channel.
    static let accuracyWeight: Double = 20
    /// Max ENGAGEMENT (momentum) points per channel.
    static let engagementMax: Int = 5
    /// Rising / All-Star / MVP lower bounds. `Fan` is anything below the first. Must stay ascending.
    static let tierThresholds: [Int] = [25, 50, 75]

    /// ⚠️ TOP-WEIGHTED ACCURACY CURVE — the exponent on each channel's accuracy ratio before ×20
    /// (`points = ratio^gamma × 20`). `gamma > 1` makes the TOP of the scale genuinely HARD to reach
    /// (only near-elite accuracy earns the last few points), which is the owner's core law: don't hand
    /// out points, keep the ceiling meaningful all season ([[feedback_superfan_points_philosophy]]).
    /// Calibrated to each game's LUCK vs SKILL: KHG/Trivia are pure knowledge → steeper (the top demands
    /// excellence); Predict (≈75% luck) and Bracket (≈70% vibes) are gentler (≈linear) so a good-given-
    /// luck week is fairly credited AND the games' natural low accuracy ceiling already keeps them hard.
    /// FIRST-PASS values — lean stingy, tune live on real distributions.
    static let accuracyGamma: [SuperfanGame: Double] = [
        .predict: 1.05, .bracket: 1.05, .khg: 1.30, .trivia: 1.30
    ]

    // MARK: - Derivation

    /// Raw accuracy 0…1 for a game (0 when nothing attempted).
    static func accuracy(for game: SuperfanGame, counts: SuperfanCounts) -> Double {
        let (correct, total) = counts.pair(for: game)
        return total > 0 ? Double(correct) / Double(total) : 0
    }

    /// The 0…20 accuracy points for a channel: `ratio^gamma × 20` (the top-weighted curve — see
    /// `accuracyGamma`). Clamped so it can't exceed the weight (covers a transient bracket edge where a
    /// just-tallied round could briefly make correct picks exceed the denominator). Note `1.0^gamma == 1`,
    /// so a perfect ratio still earns the full 20 — the curve only makes the MIDDLE cost more.
    static func accuracyPoints(for game: SuperfanGame, counts: SuperfanCounts) -> Double {
        let ratio = min(1.0, max(0.0, accuracy(for: game, counts: counts)))
        return pow(ratio, accuracyGamma[game] ?? 1.0) * accuracyWeight
    }

    /// The 0…5 engagement points for a channel (the forgiving momentum, clamped).
    static func engagementPoints(for game: SuperfanGame, counts: SuperfanCounts) -> Int {
        min(engagementMax, max(0, counts.momentum(for: game)))
    }

    /// A channel's 0…25 contribution = accuracy points + engagement points.
    static func contribution(for game: SuperfanGame, counts: SuperfanCounts) -> Double {
        let raw = accuracyPoints(for: game, counts: counts) + Double(engagementPoints(for: game, counts: counts))
        return min(SuperfanGame.maxContribution, max(0, raw))
    }

    /// The 0–100 RAW Superfan total = Σ of the four contributions, rounded, clamped. (The DISPLAYED score
    /// is `displayScore`, which applies the tier-floor lock.)
    static func total(counts: SuperfanCounts) -> Int {
        let sum = SuperfanGame.allCases.reduce(0.0) { $0 + contribution(for: $1, counts: counts) }
        return min(100, max(0, Int(sum.rounded())))
    }

    /// The highest tier floor a `peakScore` has earned this season (0 if still Fan). Used for the lock.
    static func tierFloor(peakScore: Int) -> Int {
        tierThresholds.filter { $0 <= peakScore }.max() ?? 0
    }

    /// The DISPLAYED score: the raw total, but never below a tier you've reached this season. `seasonPeak`
    /// is the monotonic `season_history.peak_score`. Since the peak is ≥ every total, this only ever holds
    /// the number up at a tier boundary you crossed and later regressed past — never invents progress.
    static func displayScore(counts: SuperfanCounts, seasonPeak: Int) -> Int {
        max(total(counts: counts), tierFloor(peakScore: seasonPeak))
    }

    /// The full breakdown for the UI in one pass.
    static func breakdown(counts: SuperfanCounts) -> SuperfanBreakdown {
        var channels: [SuperfanGame: SuperfanBreakdown.Channel] = [:]
        for game in SuperfanGame.allCases {
            channels[game] = SuperfanBreakdown.Channel(
                accuracyPoints: accuracyPoints(for: game, counts: counts),
                engagementPoints: engagementPoints(for: game, counts: counts),
                accuracyRatio: min(1.0, max(0.0, accuracy(for: game, counts: counts))))
        }
        return SuperfanBreakdown(channels: channels, total: total(counts: counts))
    }
}
