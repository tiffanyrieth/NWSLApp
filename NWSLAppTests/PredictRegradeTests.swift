//
//  PredictRegradeTests.swift
//  NWSLAppTests
//
//  The scoreline stamp on `PredictionScore` (2026-07-30) and the rule it enables: a grade computed
//  against the WRONG result must be detectable after the fact.
//
//  Why it exists — the real case. UTA v WAS was suspended for lightning at 27'; ESPN reported
//  `state == "post"`, so the app graded the owner's XI against a fake 0–0. The XI half was unaffected
//  (the starting XI was posted before the delay and never changed) but `resultCorrect` was judged
//  against a DRAW, so a correct "Washington win" call scored 0. The match finished 0–1 — an actual
//  Washington win — and the card still LOOKED right, because the "Actual 0–1" it renders comes from
//  the live event rather than from the grade. Three points, silently lost, with nothing to detect it.
//
//  These tests pin the comparison itself. The clearing path lives in `PredictXIViewModel`
//  (`regradeStaleScores`), which needs a live store + event graph; what's testable in isolation — and
//  what actually went wrong — is whether a stamped grade can be told apart from reality.
//

import Foundation
import Testing
@testable import NWSLApp

// `PredictionScore`'s Codable conformance is main-actor isolated, so the round-trip cases must run
// there too — nonisolated use is a warning today and an error under the Swift 6 language mode.
@MainActor
struct PredictRegradeTests {

    /// The owner's real prediction: called UTA 1–2 (a one-goal Washington win).
    private func ownersScore(gradedHome: Int?, gradedAway: Int?) -> PredictionScore {
        PredictionScore(correctPlayers: 7, correctPositions: 6,
                        formationCorrect: false, exactScoreline: false,
                        resultCorrect: false,   // graded against 0–0 ⇒ a draw ⇒ "Washington win" missed
                        perfectXI: false,
                        gradedHomeScore: gradedHome, gradedAwayScore: gradedAway)
    }

    private func isStale(_ score: PredictionScore, actualHome: Int, actualAway: Int) -> Bool {
        guard let h = score.gradedHomeScore, let a = score.gradedAwayScore else { return false }
        return h != actualHome || a != actualAway
    }

    @Test func aGradeStampedWithADifferentScorelineIsStale() {
        // Graded at the fake 0–0; the match actually finished 0–1.
        #expect(isStale(ownersScore(gradedHome: 0, gradedAway: 0), actualHome: 0, actualAway: 1))
    }

    @Test func aGradeStampedWithTheRealScorelineIsNotStale() {
        #expect(!isStale(ownersScore(gradedHome: 0, gradedAway: 1), actualHome: 0, actualAway: 1))
    }

    @Test func anUnstampedGradeIsNeverStale() {
        // ⚠️ POLARITY. nil means "graded before the stamp existed", NOT "re-grade me". Treating nil as
        // stale would invalidate every score persisted before this shipped — a far worse bug than the
        // one being fixed.
        #expect(!isStale(ownersScore(gradedHome: nil, gradedAway: nil), actualHome: 3, actualAway: 0))
    }

    @Test func eitherSideChangingCountsAsStale() {
        #expect(isStale(ownersScore(gradedHome: 1, gradedAway: 1), actualHome: 2, actualAway: 1))
        #expect(isStale(ownersScore(gradedHome: 1, gradedAway: 1), actualHome: 1, actualAway: 2))
    }

    // MARK: - The three points that were actually lost

    @Test func theResultComponentIsWhatTheFakeDrawCost() {
        // Everything except `resultCorrect` grades identically against 0–0 and 0–1, because the XI was
        // already final and both formation and exact score were misses either way. So the entire
        // discrepancy is one flag worth `resultPointsValue`.
        let asGraded = ownersScore(gradedHome: 0, gradedAway: 0)
        var regraded = asGraded
        regraded.resultCorrect = true          // 1–2 and 0–1 are both one-goal Washington wins
        #expect(asGraded.total == 33)
        #expect(regraded.total == 36)
        #expect(regraded.total - asGraded.total == PredictionScore.resultPointsValue)
    }

    @Test func theStampSurvivesACodableRoundTrip() {
        // It's persisted in UserDefaults with the rest of the score; a stamp that didn't round-trip
        // would silently disable the whole check.
        let score = ownersScore(gradedHome: 0, gradedAway: 1)
        let decoded = try! JSONDecoder().decode(PredictionScore.self,
                                                from: try! JSONEncoder().encode(score))
        #expect(decoded.gradedHomeScore == 0)
        #expect(decoded.gradedAwayScore == 1)
    }

    @Test func anOlderPersistedScoreStillDecodes() {
        // A grade written before the stamp existed has no such keys — it must decode with nils rather
        // than failing, or every historical score would be lost on upgrade.
        let legacy = #"{"correctPlayers":7,"correctPositions":6,"formationCorrect":false,"exactScoreline":false,"resultCorrect":true,"perfectXI":false}"#
        let decoded = try! JSONDecoder().decode(PredictionScore.self, from: Data(legacy.utf8))
        #expect(decoded.gradedHomeScore == nil)
        #expect(decoded.correctPlayers == 7)
        #expect(decoded.total == 36)
    }
}
