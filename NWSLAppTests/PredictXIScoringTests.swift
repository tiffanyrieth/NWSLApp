//
//  PredictXIScoringTests.swift
//  NWSLAppTests
//
//  Covers the pure Predict the XI scorer (PredictionScoring.score) — every
//  Mastermind weight, the exact-scoreline / result STACK, and the perfect-XI
//  bonus — on hand-built answer keys, plus one end-to-end check that an
//  `ActualResult` builds from a real captured ESPN `/summary` and scores a full
//  correct XI as expected. The latter proves the auto-score path against real
//  data even while the league is mid-break (no upcoming matches to settle live).
//

import Foundation
import Testing
@testable import NWSLApp

struct PredictXIScoringTests {

    // MARK: - Synthetic answer key (full control over groups)

    /// A 4-3-3 XI with deterministic ids "a0"…"a10": a0 GK, a1–a4 DEF, a5–a7 MID,
    /// a8–a10 FWD — matching the 4-3-3 slot bands exactly.
    private func actual4333(homeScore: Int = 2, awayScore: Int = 1) -> ActualResult {
        let groups: [PositionGroup] = [.gk] + Array(repeating: .def, count: 4)
            + Array(repeating: .mid, count: 3) + Array(repeating: .fwd, count: 3)
        let starters = groups.enumerated().map {
            ActualResult.Starter(athleteID: "a\($0.offset)", group: $0.element)
        }
        return ActualResult(formation: "4-3-3", starters: starters,
                            homeScore: homeScore, awayScore: awayScore)
    }

    /// A prediction; by default a PERFECT 4-3-3 (every slot index → the matching id
    /// "a{index}", correct formation, exact 2–1).
    private func prediction(
        formation: String = "4-3-3",
        slots: [Int: String]? = nil,
        home: Int = 2, away: Int = 1
    ) -> XIPrediction {
        let filled = slots ?? Dictionary(uniqueKeysWithValues: (0...10).map { ($0, "a\($0)") })
        return XIPrediction(fixtureID: "e1-WAS", eventID: "e1", teamAbbreviation: "WAS",
                            formation: formation, slots: filled,
                            homeScoreGuess: home, awayScoreGuess: away, state: .submitted)
    }

    @Test func perfectPredictionScoresTheMax() {
        let s = PredictionScoring.score(prediction(), against: actual4333())
        #expect(s.correctPlayers == 11)
        #expect(s.correctPositions == 11)
        #expect(s.formationCorrect)
        #expect(s.exactScoreline)
        #expect(s.resultCorrect)
        #expect(s.perfectXI)
        // 33 + 22 + 5 + 10 + 3 + 15 = 88 (the documented ceiling).
        #expect(s.total == 88)
    }

    @Test func eachCorrectPlayerIsThreeAndPositionBonusNeedsACorrectPlayer() {
        // Pick only 5 real starters (a0…a4), the other 6 slots are non-starters.
        var slots = Dictionary(uniqueKeysWithValues: (0...4).map { ($0, "a\($0)") })
        for i in 5...10 { slots[i] = "ghost\(i)" }   // not in the XI
        let s = PredictionScoring.score(prediction(slots: slots), against: actual4333())
        #expect(s.correctPlayers == 5)
        #expect(s.playersPoints == 15)
        // a0…a4 are GK + 4 DEF, slotted in their own bands → all 5 position bonuses.
        #expect(s.correctPositions == 5)
        #expect(s.positionsPoints == 10)
        #expect(!s.perfectXI)
    }

    @Test func rightPlayerWrongBandEarnsNoPositionBonus() {
        // Put forward a8 in a DEF slot (index 1) and a defender a1 in a FWD slot
        // (index 8) — both are correct PLAYERS, neither sits in the right band.
        var slots = Dictionary(uniqueKeysWithValues: (0...10).map { ($0, "a\($0)") })
        slots[1] = "a8"; slots[8] = "a1"
        let s = PredictionScoring.score(prediction(slots: slots), against: actual4333())
        #expect(s.correctPlayers == 11)          // still all real starters
        #expect(s.correctPositions == 9)         // the two swapped slots lose their bonus
        #expect(s.perfectXI)                     // perfect is about PLAYERS, not bands
    }

    @Test func wrongFormationLosesFivePoints() {
        let s = PredictionScoring.score(prediction(formation: "4-4-2"), against: actual4333())
        #expect(!s.formationCorrect)
        #expect(s.formationPoints == 0)
    }

    @Test func exactScorelineAndResultStack() {
        // Predict 2–1, actual 2–1 → both fire (+10 exact, +3 result).
        let exact = PredictionScoring.score(prediction(home: 2, away: 1), against: actual4333(homeScore: 2, awayScore: 1))
        #expect(exact.exactScoreline)
        #expect(exact.resultCorrect)
        #expect(exact.scorelinePoints + exact.resultPoints == 13)
    }

    @Test func rightResultWrongScoreIsResultOnly() {
        // Predict 2–1 (home win), actual 3–0 (home win) → result only, no exact.
        let s = PredictionScoring.score(prediction(home: 2, away: 1), against: actual4333(homeScore: 3, awayScore: 0))
        #expect(!s.exactScoreline)
        #expect(s.resultCorrect)
        #expect(s.resultPoints == 3)
        #expect(s.scorelinePoints == 0)
    }

    @Test func wrongResultScoresNeitherScorelineNorResult() {
        // Predict 2–1 (home win), actual 0–1 (away win).
        let s = PredictionScoring.score(prediction(home: 2, away: 1), against: actual4333(homeScore: 0, awayScore: 1))
        #expect(!s.exactScoreline)
        #expect(!s.resultCorrect)
        #expect(s.scorelinePoints == 0 && s.resultPoints == 0)
    }

    @Test func drawIsItsOwnResult() {
        let s = PredictionScoring.score(prediction(home: 1, away: 1), against: actual4333(homeScore: 1, awayScore: 1))
        #expect(s.exactScoreline)
        #expect(s.resultCorrect)
    }

    // MARK: - Real ESPN /summary (proves the live answer-key build)

    private func loadSummary() throws -> MatchSummary {
        let fixture = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures/summary.json")
        return try JSONDecoder().decode(MatchSummary.self, from: Data(contentsOf: fixture))
    }

    @Test func actualResultBuildsFromRealSummaryAndScoresAFullXI() throws {
        let summary = try loadSummary()
        // Fixture is WAS 1–1 POR; predict the HOME (WAS) side.
        let actual = try #require(ActualResult.make(from: summary, isHome: true, homeScore: 1, awayScore: 1))
        #expect(actual.starters.count == 11)
        #expect(actual.formation == "4-2-3-1")

        // Pick the real 11 starters (slot index i → the i-th actual starter), with
        // the right formation + exact score → a guaranteed full + perfect XI. We
        // don't assert the position bonus here: whether the front three tag as AM
        // (mid) or RW/LW (fwd) is ESPN's call, so the band-match count is left to
        // the synthetic tests above.
        let slots = Dictionary(uniqueKeysWithValues:
            actual.starters.enumerated().map { ($0.offset, $0.element.athleteID) })
        let prediction = XIPrediction(
            fixtureID: "real-WAS", eventID: "real", teamAbbreviation: "WAS",
            formation: "4-2-3-1", slots: slots,
            homeScoreGuess: 1, awayScoreGuess: 1, state: .submitted
        )

        let score = PredictionScoring.score(prediction, against: actual)
        #expect(score.correctPlayers == 11)     // every pick really started
        #expect(score.perfectXI)
        #expect(score.formationCorrect)
        #expect(score.exactScoreline)
        #expect(score.resultCorrect)
        #expect((0...11).contains(score.correctPositions))
        // Everything but the (data-dependent) position bonus is locked in:
        // 33 players + 5 formation + 10 scoreline + 3 result + 15 perfect = 66.
        #expect(score.total >= 66)
    }
}
