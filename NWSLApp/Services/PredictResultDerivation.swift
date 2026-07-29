//
//  PredictResultDerivation.swift
//  NWSLApp
//
//  Rebuilds the per-pick detail of a scored Predict the XI match from the re-fetched actual lineup
//  (results redesign, 2026-07-28). Pure — no state, no I/O, no UI — the deliberate sibling shape of
//  `PredictionScoring.swift`, which computes the same comparison and then throws the per-pick part
//  away because only aggregates are persisted.
//
//  ⚠️ THIS MUST AGREE WITH THE SCORER, ALWAYS. Two places now compare a prediction against the same
//  answer key: `PredictionScoring.score` (which produces the points the user is ranked on) and this
//  (which produces the ✓/✗ the user reads). If they ever disagree, the screen contradicts the
//  scoreboard directly above it — a pitch showing 9 green nodes over a breakdown row reading
//  "Correct players 8/11". `PredictResultDerivationTests` pins the agreement over generated inputs
//  rather than trusting the two implementations to stay in step by inspection.
//

import Foundation

enum PredictResultDerivation {

    // MARK: - Per-pick states

    /// Grade every filled slot of `prediction` against `actual`.
    ///
    /// The hit test is `actual.starterIDs.contains(id)` — SET-WISE, matching the scorer exactly.
    /// The band check is secondary and only distinguishes which KIND of hit it was; it never
    /// downgrades a hit to a miss. Returns picks in slot order (GK first), which is the order the
    /// grouped list renders and the order the pitch reads its nodes from.
    static func picks(for prediction: XIPrediction,
                      against actual: ActualResult,
                      names: [String: String],
                      community: PredictCommunity? = nil) -> [PredictPickResult] {
        guard let formation = Formation(raw: prediction.formation) else { return [] }
        let starterIDs = actual.starterIDs

        return formation.slots.compactMap { slot in
            guard let athleteID = prediction.slots[slot.index] else { return nil }
            let state: PredictPickResult.State
            if !starterIDs.contains(athleteID) {
                state = .didNotStart
            } else if let actualGroup = actual.group(forAthlete: athleteID), actualGroup != slot.group {
                state = .startedOffBand(actual: actualGroup)
            } else {
                // Started, and either the bands match or ESPN gave us no position for her. An
                // unknown position falls to the GENEROUS side on purpose: the scorer only awards
                // the +2 when both groups are known and equal, but claiming "she played out of
                // position" on missing data would be asserting something we don't know.
                state = .startedInBand
            }
            return PredictPickResult(
                slot: slot,
                athleteID: athleteID,
                name: names[athleteID] ?? "Player",
                state: state,
                communityShare: community?.share(forPlayer: athleteID)
            )
        }
    }

    /// Actual starters the user picked nowhere in her XI.
    static func missedStarters(for prediction: XIPrediction,
                               against actual: ActualResult,
                               names: [String: String],
                               community: PredictCommunity? = nil) -> [PredictMissedStarter] {
        let picked = prediction.pickedAthleteIDs
        return actual.starters
            .filter { !picked.contains($0.athleteID) }
            .map { starter in
                PredictMissedStarter(
                    athleteID: starter.athleteID,
                    name: names[starter.athleteID] ?? "Player",
                    group: starter.group,
                    communityShare: community?.share(forPlayer: starter.athleteID)
                )
            }
    }

    // MARK: - Standout picks

    /// The gutsiest call that came off, and the obvious name you left out.
    ///
    /// Both require real community data — with no shares there is no "only 14% had her", and
    /// inventing one would be fabricating the entire point of the card. Both also require the
    /// share to be genuinely notable: a hit everybody had is not a standout, and a miss nobody
    /// wanted is not an indictment. When neither qualifies the section renders nothing.
    static func standouts(picks: [PredictPickResult],
                          missed: [PredictMissedStarter],
                          hitCeiling: Double = 0.50,
                          missFloor: Double = 0.50) -> PredictStandouts {
        let hit = picks
            .filter { $0.state.started }
            .compactMap { pick -> (PredictPickResult, Double)? in
                // ⚠️ `share > 0` is a DATA-INTEGRITY guard, not a threshold. You picked her, and the
                // aggregate counts your own submission, so a 0% share on one of your own picks is
                // impossible — it means the distribution we got back is partial. Without this, the
                // "gutsiest call" card would name whichever of your picks happened to be missing
                // from the payload, stated as fact.
                guard let share = pick.communityShare, share > 0, share <= hitCeiling else { return nil }
                return (pick, share)
            }
            // Lowest share wins; ties break on id so the same match always names the same player.
            .min { $0.1 == $1.1 ? $0.0.athleteID < $1.0.athleteID : $0.1 < $1.1 }?.0

        let miss = missed
            .compactMap { starter -> (PredictMissedStarter, Double)? in
                guard let share = starter.communityShare, share >= missFloor else { return nil }
                return (starter, share)
            }
            .max { $0.1 == $1.1 ? $0.0.athleteID > $1.0.athleteID : $0.1 < $1.1 }?.0

        return PredictStandouts(hit: hit, miss: miss)
    }

    // MARK: - Aggregates the summary card reads

    /// Starters called — the hero number. Set-wise, so it equals `PredictionScore.correctPlayers`.
    static func startersCalled(_ picks: [PredictPickResult]) -> Int {
        picks.filter { $0.state.started }.count
    }

    /// Per-band "3/4" counts for the grouped list's section headers, in GK → attack order.
    static func bandTallies(_ picks: [PredictPickResult]) -> [(group: PositionGroup, started: Int, total: Int)] {
        PositionGroup.allCases.compactMap { group in
            let inBand = picks.filter { $0.slot.group == group }
            guard !inBand.isEmpty else { return nil }
            return (group, inBand.filter { $0.state.started }.count, inBand.count)
        }
    }
}
