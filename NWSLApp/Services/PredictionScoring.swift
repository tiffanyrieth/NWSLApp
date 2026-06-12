//
//  PredictionScoring.swift
//  NWSLApp
//
//  The Predict the XI scorer — Fan Zone game 1 (0.3.9). A single PURE function:
//  given the user's `XIPrediction` and the match's `ActualResult`, return the
//  `PredictionScore` breakdown. No state, no I/O — so every scoring rule is unit-
//  testable in isolation (PredictXIScoringTests), and the view model just calls it
//  once a submitted prediction's match has settled.
//
//  Mastermind-style partial points (owner-set weights):
//    • each correct XI player              +3  (≤ 33)
//    • correct position band for one        +2  (only if that player is also correct)
//    • correct formation                    +5
//    • exact scoreline                     +10   ┐ these STACK — predicting 2–1 and
//    • correct result (W/D/L)               +3   ┘ getting 2–1 scores both (+13)
//    • perfect XI (all 11)                 +15
//

import Foundation

enum PredictionScoring {
    /// Grade a prediction against the actual lineup + score. "Correct position"
    /// is intentionally band-level (GK/DEF/MID/FWD) and only granted when the
    /// player is also a correct XI pick — see PositionGroup / the plan.
    static func score(_ prediction: XIPrediction, against actual: ActualResult) -> PredictionScore {
        let actualIDs = actual.starterIDs
        let formation = Formation(raw: prediction.formation)

        var correctPlayers = 0
        var correctPositions = 0

        for (slotIndex, athleteID) in prediction.slots {
            guard actualIDs.contains(athleteID) else { continue }
            correctPlayers += 1
            // Position bonus: did we slot them in the band they actually played?
            if let predictedGroup = formation?.slot(at: slotIndex)?.group,
               let actualGroup = actual.group(forAthlete: athleteID),
               predictedGroup == actualGroup {
                correctPositions += 1
            }
        }

        let formationCorrect = actual.formation.map { normalize($0) == normalize(prediction.formation) } ?? false

        let exactScoreline = prediction.homeScoreGuess == actual.homeScore
            && prediction.awayScoreGuess == actual.awayScore

        let resultCorrect = outcome(prediction.homeScoreGuess, prediction.awayScoreGuess)
            == outcome(actual.homeScore, actual.awayScore)

        return PredictionScore(
            correctPlayers: correctPlayers,
            correctPositions: correctPositions,
            formationCorrect: formationCorrect,
            exactScoreline: exactScoreline,
            resultCorrect: resultCorrect,
            perfectXI: correctPlayers == 11
        )
    }

    // MARK: - Helpers

    /// W/D/L from a scoreline's sign (home perspective; symmetric so it's the same
    /// verdict for either side's prediction of the same match).
    private enum Outcome { case homeWin, draw, awayWin }
    private static func outcome(_ home: Int, _ away: Int) -> Outcome {
        if home > away { return .homeWin }
        if home < away { return .awayWin }
        return .draw
    }

    /// Compare formation strings tolerant of stray whitespace.
    private static func normalize(_ formation: String) -> String {
        formation.trimmingCharacters(in: .whitespaces)
    }
}
