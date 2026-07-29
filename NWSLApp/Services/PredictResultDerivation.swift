//
//  PredictResultDerivation.swift
//  NWSLApp
//
//  Grades the REAL starting XI against the user's prediction (results redesign; reworked 2026-07-28
//  when the pitch flipped from "your XI graded" to "the real XI, marked with what you called").
//  Pure — no state, no I/O, no UI — the deliberate sibling shape of `PredictionScoring.swift`.
//
//  ⚠️ THIS MUST AGREE WITH THE SCORER, ALWAYS. Two places compare a prediction against the same
//  answer key: `PredictionScoring.score` (the points the user is ranked on) and this (the ✓/✗ the
//  user reads). The set-wise identity that keeps them equal: the number of STARTERS YOU CALLED and
//  the number of YOUR PICKS WHO STARTED are the same set counted from either side, so
//  `startersCalled == score.correctPlayers` must hold for every input.
//  `PredictResultDerivationTests` pins that over generated inputs.
//

import Foundation

enum PredictResultDerivation {

    // MARK: - The real XI, graded

    /// Every actual starter in lineup order, marked with whether she appeared anywhere in the
    /// user's XI. Lineup order matters: `ActualResult` sorts by ESPN's formation place, which is
    /// what lets the pitch map starter i → formation slot i.
    static func starterResults(for prediction: XIPrediction,
                               against actual: ActualResult,
                               names: [String: String],
                               community: PredictCommunity? = nil) -> [PredictStarterResult] {
        let picked = prediction.pickedAthleteIDs
        return actual.starters.map { starter in
            PredictStarterResult(
                athleteID: starter.athleteID,
                name: names[starter.athleteID] ?? "Player",
                group: starter.group,
                called: picked.contains(starter.athleteID),
                communityShare: community?.share(forPlayer: starter.athleteID)
            )
        }
    }

    /// The user's picks who did not start — the busts. One quiet line on the screen, never a
    /// whole section: the pitch already tells the real story.
    static func busts(for prediction: XIPrediction,
                      against actual: ActualResult,
                      names: [String: String],
                      community: PredictCommunity? = nil) -> [PredictBust] {
        let starterIDs = actual.starterIDs
        return prediction.pickedAthleteIDs
            .filter { !starterIDs.contains($0) }
            .sorted()   // deterministic order for a stable render
            .map { PredictBust(athleteID: $0,
                               name: names[$0] ?? "Player",
                               communityShare: community?.share(forPlayer: $0)) }
    }

    // MARK: - Aggregates

    /// The hero number. Set-wise ⇒ equals `PredictionScore.correctPlayers` by construction.
    static func startersCalled(_ starters: [PredictStarterResult]) -> Int {
        starters.filter(\.called).count
    }

    /// Per-band "you called 3 of the 4" tallies, GK → attack, over the ACTUAL lineup's bands.
    static func bandTallies(_ starters: [PredictStarterResult])
        -> [(group: PositionGroup, called: Int, total: Int)] {
        PositionGroup.allCases.compactMap { group in
            let inBand = starters.filter { $0.group == group }
            guard !inBand.isEmpty else { return nil }
            return (group, inBand.filter(\.called).count, inBand.count)
        }
    }

    // MARK: - Standout picks

    /// The gutsy call that came off, and the name everyone else had that you left out.
    ///
    /// Both require real community data, and both require the share to be genuinely notable.
    /// ⚠️ The hit ceiling is deliberately LOW (a third of the club, not half): an obvious pick with
    /// steady ownership — a first-choice keeper — must never be praised as gutsy just because she
    /// happened to be the least-owned thing you got right (owner, 2026-07-28).
    static func standouts(starters: [PredictStarterResult],
                          hitCeiling: Double = 0.35,
                          upsetFloor: Double = 0.50) -> PredictStandouts {
        let hit = starters
            .filter(\.called)
            .compactMap { starter -> (PredictStarterResult, Double)? in
                // share > 0 is a DATA-INTEGRITY guard: the aggregate counts your own submission, so
                // a 0% share on someone you called means the distribution is partial — never a fact.
                guard let share = starter.communityShare, share > 0, share <= hitCeiling else { return nil }
                return (starter, share)
            }
            .min { $0.1 == $1.1 ? $0.0.athleteID < $1.0.athleteID : $0.1 < $1.1 }?.0

        let upset = starters
            .filter { !$0.called }
            .compactMap { starter -> (PredictStarterResult, Double)? in
                guard let share = starter.communityShare, share >= upsetFloor else { return nil }
                return (starter, share)
            }
            .max { $0.1 == $1.1 ? $0.0.athleteID > $1.0.athleteID : $0.1 < $1.1 }?.0

        return PredictStandouts(hit: hit, upset: upset)
    }
}
