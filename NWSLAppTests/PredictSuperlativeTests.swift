//
//  PredictSuperlativeTests.swift
//  NWSLAppTests
//
//  The one optional line of praise on a Predict result. It is the highest-risk copy in the feature —
//  the place where a fabricated or tone-deaf line would do the most damage — so its rules are pinned
//  here rather than left to inspection:
//
//   1. It must be TRUE — every rung is a real comparison, and the season-best rungs need a real
//      prior baseline. A user's FIRST result must never claim to be a personal best.
//   2. It must never surface a DEFICIT — no rung for "the crowd beat you", and nothing below the
//      50th percentile. This slot is a reward state; a shortfall in it is a churn mechanic.
//   3. When nothing is true it renders NOTHING. If "your best match of the season" can fire on a
//      mediocre match, it's worthless on the day it's real.
//

import Foundation
import Testing
@testable import NWSLApp

struct PredictSuperlativeTests {

    private func match(startersCalled: Int = 6,
                       previousBest: Int? = nil,
                       consensus: Int? = nil,
                       perfectBands: [PredictSuperlative.PerfectBand] = []) -> PredictSuperlative.MatchInput {
        .init(startersCalled: startersCalled, previousBestStarters: previousBest,
              consensusStarters: consensus, perfectBands: perfectBands)
    }

    // MARK: - Nothing true → nothing rendered

    @Test func rendersNothingWhenNoRungIsTrue() {
        // A middling match: no baseline beaten, crowd did better, no perfect line.
        #expect(PredictSuperlative.forMatch(match(startersCalled: 5, previousBest: 9,
                                                  consensus: 8)) == nil)
    }

    /// ⚠️ The single most important guard. With no prior baseline, "your best match of the season"
    /// would fire on every user's first result and the phrase would mean nothing thereafter.
    @Test func aFirstResultNeverClaimsASeasonBest() {
        #expect(PredictSuperlative.forMatch(match(startersCalled: 11, previousBest: nil)) != "Your best match of the season")
        #expect(PredictSuperlative.forMatch(match(startersCalled: 11, previousBest: 0)) != "Your best match of the season")
    }

    // MARK: - Rung order

    @Test func aGenuineSeasonBestOutranksEverythingElse() {
        let line = PredictSuperlative.forMatch(match(startersCalled: 10, previousBest: 8,
                                                     consensus: 5))
        #expect(line == "Your best match of the season")
    }

    @Test func beatingTheConsensusOutranksAPerfectLine() {
        let line = PredictSuperlative.forMatch(match(
            startersCalled: 9, previousBest: 10, consensus: 8,
            perfectBands: [.init(group: .def, slots: 4)]))
        #expect(line == "Beat the consensus XI")
    }

    @Test func matchingTheConsensusIsItsOwnRung() {
        #expect(PredictSuperlative.forMatch(match(startersCalled: 8, previousBest: 10, consensus: 8))
                == "Matched the consensus XI")
    }

    /// ⚠️ There is deliberately NO rung for the crowd outscoring the user — that case falls through
    /// to the next rung, or to nothing.
    @Test func losingToTheConsensusIsNeverStated() {
        let line = PredictSuperlative.forMatch(match(startersCalled: 4, previousBest: 10, consensus: 9))
        #expect(line == nil)
    }

    // MARK: - Perfect lines

    @Test func aFullyCalledLineFiresWhenNothingAboveIt() {
        let line = PredictSuperlative.forMatch(match(
            startersCalled: 7, previousBest: 10, consensus: 9,
            perfectBands: [.init(group: .mid, slots: 3)]))
        #expect(line == "Perfect midfield")
    }

    /// A one-slot line can't qualify — "Perfect goalkeeping" for a single correct pick is meaningless.
    @Test func aSingleSlotLineNeverQualifies() {
        let line = PredictSuperlative.forMatch(match(
            startersCalled: 7, previousBest: 10, consensus: 9,
            perfectBands: [.init(group: .gk, slots: 1)]))
        #expect(line == nil)
    }

    @Test func theWidestQualifyingLineWins() {
        let line = PredictSuperlative.forMatch(match(
            startersCalled: 8, previousBest: 10, consensus: 9,
            perfectBands: [.init(group: .mid, slots: 3), .init(group: .def, slots: 4)]))
        #expect(line == "Perfect defense")
    }

    /// ⚠️ The percentile branch was CUT in the owner review (2026-07-28): "Ahead of 76%…" restated
    /// the rank row beneath it in vaguer language. With every higher rung false, the slot renders
    /// nothing — never a duplicate of the rank.
    @Test func aGoodRankAloneRendersNothing() {
        #expect(PredictSuperlative.forMatch(match(startersCalled: 6, previousBest: 10,
                                                   consensus: 9)) == nil)
    }

    // MARK: - Round ladder

    @Test func roundBestNeedsARealBaselineToo() {
        #expect(PredictSuperlative.forRound(.init(startersCalled: 25, previousBestStarters: nil,
                                                   clubsImproved: 0, clubsScored: 3)) == nil)
        #expect(PredictSuperlative.forRound(.init(startersCalled: 25, previousBestStarters: 20,
                                                   clubsImproved: 0, clubsScored: 3))
                == "Your best round of the season")
    }

    @Test func improvedClubsAreReportedWhenNoRoundBest() {
        #expect(PredictSuperlative.forRound(.init(startersCalled: 10, previousBestStarters: 25,
                                                   clubsImproved: 3, clubsScored: 3))
                == "3 of 3 clubs improved their rank")
        #expect(PredictSuperlative.forRound(.init(startersCalled: 10, previousBestStarters: 25,
                                                   clubsImproved: 1, clubsScored: 1))
                == "1 of 1 club improved their rank")
    }

    @Test func noClubImprovingRendersNothing() {
        #expect(PredictSuperlative.forRound(.init(startersCalled: 10, previousBestStarters: 25,
                                                   clubsImproved: 0, clubsScored: 3)) == nil)
    }

    // MARK: - Season bests merging

    @Test func bestsMergeUpwardsOnly() {
        let stored = PredictSeasonBests(season: "2026", bestMatchStarters: 9, bestRoundStarters: 24)
        let lower = PredictSeasonBests(season: "2026", bestMatchStarters: 3, bestRoundStarters: 5)
        #expect(stored.merged(with: lower) == stored)

        let higher = PredictSeasonBests(season: "2026", bestMatchStarters: 10, bestRoundStarters: 20)
        let merged = stored.merged(with: higher)
        #expect(merged.bestMatchStarters == 10)   // raised
        #expect(merged.bestRoundStarters == 24)   // held
    }

    /// A personal best belongs to its season. Carrying last year's forward would make the rung
    /// unreachable every March.
    @Test func aNewSeasonResetsRatherThanCarryingForward() {
        let lastYear = PredictSeasonBests(season: "2025", bestMatchStarters: 11, bestRoundStarters: 30)
        let thisYear = PredictSeasonBests(season: "2026", bestMatchStarters: 4, bestRoundStarters: 8)
        #expect(lastYear.merged(with: thisYear) == thisYear)
    }

    @Test func aZeroMarkIsNotABaseline() {
        let empty = PredictSeasonBests.empty(season: "2026")
        #expect(empty.hasMatchBaseline == false)
        #expect(empty.hasRoundBaseline == false)
    }
}
