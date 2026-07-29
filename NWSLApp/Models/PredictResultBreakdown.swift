//
//  PredictResultBreakdown.swift
//  NWSLApp
//
//  The graded view of a scored Predict the XI match (results redesign; reworked 2026-07-28 after the
//  owner's first-pass review).
//
//  ⚠️ THE PITCH SHOWS THE REAL XI, NOT YOUR GUESS (owner call). The game is named "Predict the XI" —
//  the moment is seeing the actual lineup and how much of it you called, not re-reading your own
//  picks. So the primary unit here is a STARTER (someone who really played) marked called/missed,
//  and your picks who sat are a small separate list of "busts". This also dissolved the old
//  "Also started — you missed" section: a starter you missed is simply an unmarked node on the pitch.
//
//  ⚠️ DERIVED, NEVER PERSISTED. `PredictionScore` stores only aggregate counts and stays that way;
//  everything here is rebuilt at view time from the re-fetched lineup.
//
//  ⚠️ CALLED IS SET-WISE, exactly like the scorer's hit test: you called her if she was anywhere in
//  your XI, regardless of the slot. The +2 position bonus surfaces ONLY as the aggregate breakdown
//  row — the per-player amber "played MID" state was cut (owner: it read as a third kind of wrong
//  and cluttered the pitch; the subtlety belongs in the points table, not on a face).
//

import Foundation

// MARK: - One actual starter, graded against your XI

struct PredictStarterResult: Identifiable, Equatable {
    let athleteID: String
    let name: String
    /// The band she actually started in — drives the pitch row and the band panels.
    let group: PositionGroup
    /// True when she appeared ANYWHERE in your XI (set-wise, matching the scorer).
    let called: Bool
    /// Share of the club's fans who had her in their XI, 0…1. nil while community data is sealed
    /// or unavailable — and only ever RENDERED inside a labeled panel, never as a bare number.
    var communityShare: Double?

    var id: String { athleteID }
}

// MARK: - Your picks who didn't start

struct PredictBust: Identifiable, Equatable {
    let athleteID: String
    let name: String
    var communityShare: Double?

    var id: String { athleteID }
}

// MARK: - Standout picks

/// The two "worth telling someone" moments. Either can be absent → its card isn't drawn.
struct PredictStandouts: Equatable {
    /// A starter you called that few others backed — the gutsy call that came off.
    let hit: PredictStarterResult?
    /// A starter most of the club had that you left out — the upset (owner rename from "miss").
    let upset: PredictStarterResult?

    static let none = PredictStandouts(hit: nil, upset: nil)
}

// MARK: - Season high-water marks

/// The thresholds the superlative ladder compares against. Mirrors `predict_season_bests`.
///
/// Both count STARTERS, not points. Merging takes the max in both directions, matching the SQL
/// `GREATEST` — a stale device, an offline stretch or a reinstall can never lower a personal best.
struct PredictSeasonBests: Codable, Equatable {
    var season: String
    var bestMatchStarters: Int
    var bestRoundStarters: Int

    static func empty(season: String) -> PredictSeasonBests {
        PredictSeasonBests(season: season, bestMatchStarters: 0, bestRoundStarters: 0)
    }

    /// A season change RESETS rather than carries — a personal best belongs to its season.
    func merged(with other: PredictSeasonBests) -> PredictSeasonBests {
        guard other.season == season else { return other.season > season ? other : self }
        return PredictSeasonBests(season: season,
                                  bestMatchStarters: max(bestMatchStarters, other.bestMatchStarters),
                                  bestRoundStarters: max(bestRoundStarters, other.bestRoundStarters))
    }

    /// nil-vs-zero matters: an unknown baseline must never let a first result claim a season best.
    var hasMatchBaseline: Bool { bestMatchStarters > 0 }
    var hasRoundBaseline: Bool { bestRoundStarters > 0 }
}
