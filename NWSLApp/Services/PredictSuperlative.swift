//
//  PredictSuperlative.swift
//  NWSLApp
//
//  The one optional line of praise at the end of a Predict the XI result or round summary
//  (results redesign, 2026-07-28, handoff Part 3). Pure — every branch is a computed check against
//  real data, and the whole thing returns nil when nothing true is worth saying.
//
//  ⚠️ THE THREE RULES THIS ENFORCES, because this is the highest-risk copy in the feature:
//
//  1. IT MUST BE TRUE. No branch is a mood or a threshold someone guessed — each compares real
//     numbers, and the season-best rungs compare against the user's ACTUAL history
//     (`predict_season_bests`), never a hardcoded constant. A ladder with invented thresholds is
//     just flattery with extra steps.
//  2. IT MUST NEVER SURFACE A DEFICIT. There is deliberately no branch for "the crowd beat you"
//     and none below the 50th percentile. This slot is a reward state; the user reads it as
//     validation, so putting a shortfall in it would be a churn mechanic. Rank displays elsewhere
//     stay fully honest — that is a different component with a different job.
//  3. WHEN NOTHING IS TRUE IT RENDERS NOTHING. Not a placeholder, not reserved space, no fallback
//     hype — the layout closes up. If "your best match of the season" can fire on a mediocre match
//     it is worthless on the day it's real.
//
//  ⚠️ CALLERS MUST EVALUATE BEFORE MERGING this result into the season bests. Merge first and every
//  match becomes its own personal best, which is precisely the failure rule 3 exists to prevent.
//

import Foundation

enum PredictSuperlative {

    // MARK: - Per match

    struct MatchInput {
        /// Starters called this match — the ladder reads STARTERS, never points (handoff §4.3).
        let startersCalled: Int
        /// The user's best single-match starters count BEFORE this match, or nil if unknown.
        /// nil and 0 mean different things: nil means "no baseline yet", and a first match must
        /// never claim to be a season best.
        let previousBestStarters: Int?
        /// How many starters the community's consensus XI called, or nil when the aggregate is
        /// sealed or unavailable.
        let consensusStarters: Int?
        /// Bands of the REAL lineup where the user called every starter, with their sizes.
        let perfectBands: [PerfectBand]
    }

    /// A line of the real XI the user called in full ("Perfect defense" = you named every defender
    /// who started; the +2 position bonus is NOT required — that subtlety lives in the breakdown).
    /// A named type rather than a tuple: an array of labelled tuples pushed the `filter`/`max(by:)`
    /// chain below into a type-check timeout.
    struct PerfectBand: Equatable {
        let group: PositionGroup
        let slots: Int
    }

    /// The first true rung wins. Returns nil when none is.
    static func forMatch(_ input: MatchInput) -> String? {
        // 1. A genuine season best. Requires a real prior baseline.
        if let previous = input.previousBestStarters, previous > 0, input.startersCalled > previous {
            return "Your best match of the season"
        }

        // 2–3. Against the crowd. Only ever reported when the user matched or beat it — there is no
        //      "the consensus beat you" rung, by design.
        if let consensus = input.consensusStarters {
            if input.startersCalled > consensus { return "Beat the consensus XI" }
            if input.startersCalled == consensus { return "Matched the consensus XI" }
        }

        // 4. A whole line called perfectly. Minimum three slots so a lone keeper can't produce
        //    "Perfect goalkeeper", which would mean nothing; largest qualifying line wins.
        let qualifying: [PerfectBand] = input.perfectBands.filter { $0.slots >= 3 }
        let widest: PerfectBand? = qualifying.max { (a: PerfectBand, b: PerfectBand) -> Bool in
            if a.slots != b.slots { return a.slots < b.slots }
            return a.group.rawValue > b.group.rawValue
        }
        if let widest {
            return "Perfect \(bandNoun(widest.group))"
        }

        // ⚠️ NO PERCENTILE BRANCH (owner cut, 2026-07-28 — the handoff's branch 5 was removed after
        // review). "Ahead of 76%…" restated the rank row directly beneath it in vaguer language;
        // "Ranked #7 of 29 fans" is the concrete version of the same fact, and this slot's rule is
        // to render NOTHING rather than a worse duplicate.
        return nil
    }

    // MARK: - Per round

    struct RoundInput {
        /// Starters called across every match in the round.
        let startersCalled: Int
        /// The user's best round starters count BEFORE this round, or nil if unknown.
        let previousBestStarters: Int?
        /// Clubs whose rank improved, out of how many were scored this round.
        let clubsImproved: Int
        let clubsScored: Int
    }

    static func forRound(_ input: RoundInput) -> String? {
        if let previous = input.previousBestStarters, previous > 0, input.startersCalled > previous {
            return "Your best round of the season"
        }
        if input.clubsImproved > 0, input.clubsScored > 0 {
            let clubWord = input.clubsScored == 1 ? "club" : "clubs"
            return "\(input.clubsImproved) of \(input.clubsScored) \(clubWord) improved their rank"
        }
        return nil
    }

    // MARK: - Helpers

    /// Lower-case line nouns for the "Perfect …" rung. Not on `PositionGroup` itself — this phrasing
    /// belongs to this one piece of copy, and the model's `shortLabel`/`sectionTitle` already serve
    /// the UI's other needs.
    private static func bandNoun(_ group: PositionGroup) -> String {
        switch group {
        case .gk: return "goalkeeping"
        case .def: return "defense"
        case .mid: return "midfield"
        case .fwd: return "attack"
        }
    }
}
