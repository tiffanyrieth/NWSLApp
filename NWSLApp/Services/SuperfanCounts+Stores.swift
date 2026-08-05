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

        // Trivia — season correct / attempted.
        c.triviaCorrect = trivia.seasonCorrect
        c.triviaTotal = trivia.seasonAnswered

        // Engagement momentum (0–5), FORGIVING — rewards showing up, never punishes a miss (owner ruling).
        // ⚠️ v1 = min(5, plays); it grows and never resets. The cadence-aware decay (−1 per MISSED cycle,
        // recovers on return) + server-durable per-channel play tracking is the next chunk — these local
        // signals under-count where a store prunes history, which the server merge will correct once the
        // durable counters land. KHG's play count is season-durable already; the others use local recent state.
        c.predictMomentum = min(SuperfanScoring.engagementMax, predict.scores.count)
        c.bracketMomentum = min(SuperfanScoring.engagementMax, bracket.roundScores.count)
        c.khgMomentum     = min(SuperfanScoring.engagementMax, knowHer.seasonEditionsPlayed(year: season))
        c.triviaMomentum  = min(SuperfanScoring.engagementMax, trivia.roundScores.count)

        // FAIL LOUD on an impossible pair (correct > answered): every game writes its pair together,
        // so this only arises from a sync/restore defect — the exact shape of the 2026-07-25 trivia
        // numerator-only-restore bug, which the downstream min(1,·) clamp would otherwise launder
        // into a clean "100%". The bracket is exempt: its just-tallied round can transiently exceed
        // the structure denominator (documented in SuperfanScoring.contribution).
        for (game, correct, total) in [("predict", c.predictCorrect, c.predictTotal),
                                       ("khg", c.khgCorrect, c.khgTotal),
                                       ("trivia", c.triviaCorrect, c.triviaTotal)] where correct > total {
            Diagnostics.shared.record(.fanZoneAccuracyInvariant,
                "\(game) correct \(correct) > answered \(total) at counts assembly")
        }

        return c
    }
}
