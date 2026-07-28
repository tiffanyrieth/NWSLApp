//
//  PredictResultBreakdown.swift
//  NWSLApp
//
//  The per-pick view of a scored Predict the XI match — what the redesigned results screen draws on
//  the pitch and in the grouped "Your XI" list (2026-07-28).
//
//  ⚠️ THESE ARE DERIVED, NEVER PERSISTED. `PredictionScore` deliberately stores only aggregate
//  counts (`correctPlayers`, `correctPositions` and four flags), and that stays true — widening it
//  would change a Codable shape every existing user has on disk, to cache something the screen can
//  recompute for free. The results screen already re-fetches the actual XI from `/summary`, so
//  `PredictResultDerivation` rebuilds the per-pick detail from it at view time.
//
//  ⚠️ THE THREE STATES ARE NOT "right / wrong". The scorer's hit test is SET-WISE — a pick counts
//  if she started ANYWHERE, regardless of the slot you put her in — while the +2 position bonus is
//  a separate, BAND-level check. So a player can be a hit and still miss the position points, and
//  the UI has to say that rather than imply a slot-for-slot substitution the scorer never performs.
//

import Foundation

// MARK: - One pick, graded

struct PredictPickResult: Identifiable, Equatable {
    /// How this pick turned out. Named for what HAPPENED, not for a score, so a caller can't
    /// mistake `startedOffBand` for a miss — it still banks the player's 3 points.
    enum State: Equatable {
        /// Started, in the band you played her — the full 3 + 2.
        case startedInBand
        /// Started, but in a different band — 3 points, no position bonus. Carries the band she
        /// actually played so the UI can say "started in MID" rather than a vague "wrong spot".
        case startedOffBand(actual: PositionGroup)
        /// Did not start. The only state that scores nothing.
        case didNotStart

        var started: Bool {
            if case .didNotStart = self { return false }
            return true
        }
    }

    let slot: Formation.Slot
    let athleteID: String
    let name: String
    let state: State
    /// Share of the club's predictors who picked her, 0…1. nil while the community data is sealed
    /// or unavailable — the UI then draws no bar at all rather than an empty one.
    var communityShare: Double?

    var id: Int { slot.index }
}

// MARK: - An actual starter the user didn't pick

/// Deliberately NOT attached to a slot. An actual starter you missed has no counterpart among your
/// picks — the player who really started at right-back may be someone you played in midfield, in
/// which case she is a HIT, not a replacement. These live in their own "Also started — you missed"
/// list for exactly that reason.
struct PredictMissedStarter: Identifiable, Equatable {
    let athleteID: String
    let name: String
    let group: PositionGroup
    var communityShare: Double?

    var id: String { athleteID }
}

// MARK: - Standout picks

/// The two "worth telling someone" moments of a match. Either can be absent, and then its card
/// simply isn't drawn — no placeholder, no "no standout this week".
struct PredictStandouts: Equatable {
    /// Your pick that started and that fewest others backed.
    let hit: PredictPickResult?
    /// The actual starter most of the club had, that you didn't pick at all.
    let miss: PredictMissedStarter?

    static let none = PredictStandouts(hit: nil, miss: nil)
}

// MARK: - Season high-water marks

/// The thresholds the superlative ladder compares against. Mirrors `predict_season_bests`.
///
/// Both count STARTERS, not points (handoff §4.3: the ladder reads starters-called only). Merging
/// takes the max in both directions, matching the SQL `GREATEST` — so a stale device, an offline
/// stretch or a reinstall can never lower a personal best, the same monotonic stance `SuperfanCounts`
/// takes.
struct PredictSeasonBests: Codable, Equatable {
    var season: String
    var bestMatchStarters: Int
    var bestRoundStarters: Int

    static func empty(season: String) -> PredictSeasonBests {
        PredictSeasonBests(season: season, bestMatchStarters: 0, bestRoundStarters: 0)
    }

    /// A season change RESETS rather than carries — a personal best belongs to its season, and
    /// carrying last year's forward would make the ladder unreachable every March.
    func merged(with other: PredictSeasonBests) -> PredictSeasonBests {
        guard other.season == season else { return other.season > season ? other : self }
        return PredictSeasonBests(season: season,
                                  bestMatchStarters: max(bestMatchStarters, other.bestMatchStarters),
                                  bestRoundStarters: max(bestRoundStarters, other.bestRoundStarters))
    }

    /// True when this mark has never been set — the ladder must treat "unknown" differently from
    /// "zero", or a user's very first match always claims to be a season best.
    var hasMatchBaseline: Bool { bestMatchStarters > 0 }
    var hasRoundBaseline: Bool { bestRoundStarters > 0 }
}
