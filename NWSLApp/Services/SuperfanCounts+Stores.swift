//
//  SuperfanCounts+Stores.swift
//  NWSLApp
//
//  Bridges the four Fan Zone stores into the pure Superfan economy (SuperfanScoring). Kept SEPARATE from
//  SuperfanScoring.swift so the math stays store-free + trivially testable; this is the one place that
//  knows how each game exposes its correct/attempted counts. The result is the LOCAL view of the counts,
//  which SuperfanService then GREATEST-merges into the durable `superfan_scores` row (reinstall-safe).
//
//  Each game reports correct/attempted the SAME way (accuracy = correct / attempted):
//   • Predict  — Σ correct XI players / (11 × scored matches)          (PredictionStore.scores)
//   • Bracket  — server-durable... here the LOCAL banked picks / edition-structure matchups over tallied
//                rounds (BracketScoring, missed rounds = zeros — the behavior fix). Nil pool ⇒ 0/0 locally,
//                and the server counts carry via the merge.
//   • Know Her — Σ correct answers / Σ questions attempted this season (KnowHerGameStore, per-year)
//   • Trivia   — season correct / season attempted, plus the round streak for the bonus (TriviaStore)
//

import Foundation

extension SuperfanCounts {
    /// Assemble the LOCAL per-game counts for `season` from the four stores. Local pairs are always
    /// internally consistent (correct ≤ attempted); reinstall durability is the server row's job.
    static func fromStores(season: Int,
                           predict: PredictionStore,
                           bracket: BracketStore,
                           trivia: TriviaStore,
                           knowHer: KnowHerGameStore) -> SuperfanCounts {
        var c = SuperfanCounts()

        // Predict — every scored prediction contributes 11 slots; correct = the graded XI hits.
        c.predictCorrect = predict.scores.values.reduce(0) { $0 + $1.correctPlayers }
        c.predictTotal = predict.scores.count * 11

        // Bracket — correct recovered from banked round points; denominator = matchups over tallied rounds
        // of the current edition (missed rounds included). Unknown pool ⇒ 0/0 (server counts carry).
        c.bracketCorrect = BracketScoring.correctPicks(fromRoundScores: bracket.roundScores)
        if let summary = bracket.summary, let poolSize = summary.poolSize {
            c.bracketTotal = BracketScoring.talliedMatchupDenominator(
                poolSize: poolSize, currentRoundRaw: summary.currentRoundRaw)
        } else {
            c.bracketTotal = 0
        }

        // Know Her Game — raw local season correct / attempted (year embedded in the edition key).
        c.khgCorrect = knowHer.seasonCorrectAnswers(year: season)
        c.khgTotal = knowHer.seasonAnswered(year: season)

        // Trivia — season correct / attempted, plus the current round streak (drives the +1/round bonus).
        c.triviaCorrect = trivia.seasonCorrect
        c.triviaTotal = trivia.seasonAnswered
        c.triviaStreak = trivia.streak

        return c
    }
}
