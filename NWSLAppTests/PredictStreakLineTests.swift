//
//  PredictStreakLineTests.swift
//  NWSLAppTests
//
//  The single "you're on a run" line under the Predict username. Priority: personal best → hot streak
//  → climbing, and NOTHING when none is genuinely true (the common case). These pin that it never
//  forces a line and resolves the right one.
//

import Foundation
import Testing
@testable import NWSLApp

struct PredictStreakLineTests {

    private func match(_ day: Int, _ starters: Int) -> PredictStreakLine.Match {
        PredictStreakLine.Match(kickoff: Date(timeIntervalSince1970: TimeInterval(day) * 86_400), starters: starters)
    }

    @Test func personalBestFiresWhenLatestMatchesTheSeasonHigh() {
        // Latest (day 3) is 9, the unique high of the window and equal to the season best.
        let recent = [match(1, 6), match(2, 7), match(3, 9)]
        let result = PredictStreakLine.resolve(recent: recent, bestMatchStarters: 9,
                                               hasMatchBaseline: true, bestClimb: nil)
        #expect(result?.icon == "star.fill")
        #expect(result?.text == "New season best: called 9 of 11 starters")
    }

    @Test func noPersonalBestWhenAnEarlierMatchWasHigher() {
        // The season high (10) was set earlier in the window, so the latest (8) is not a new best.
        let recent = [match(1, 10), match(2, 8)]
        let result = PredictStreakLine.resolve(recent: recent, bestMatchStarters: 10,
                                               hasMatchBaseline: true, bestClimb: nil)
        // Not a PB; not rising; no climb → nothing.
        #expect(result == nil)
    }

    @Test func hotStreakNeedsThreeRisingMatches() {
        let rising = [match(1, 3), match(2, 5), match(3, 7)]
        let result = PredictStreakLine.resolve(recent: rising, bestMatchStarters: 8,
                                               hasMatchBaseline: true, bestClimb: nil)
        #expect(result?.icon == "bolt.fill")
        #expect(result?.text == "Hot streak — 3 matches climbing")
    }

    @Test func twoRisingIsNotAStreak() {
        let two = [match(1, 4), match(2, 6)]
        let result = PredictStreakLine.resolve(recent: two, bestMatchStarters: 9,
                                               hasMatchBaseline: true, bestClimb: nil)
        #expect(result == nil)
    }

    @Test func climbingIsTheFallback() {
        let flat = [match(1, 5), match(2, 5)]
        let result = PredictStreakLine.resolve(recent: flat, bestMatchStarters: 9, hasMatchBaseline: true,
                                               bestClimb: .init(delta: 3, teamLabel: "Spirit"))
        #expect(result?.icon == "arrow.up.right")
        #expect(result?.text == "Climbed 3 on the Spirit board")
    }

    @Test func personalBestOutranksClimbing() {
        let recent = [match(1, 6), match(2, 9)]
        let result = PredictStreakLine.resolve(recent: recent, bestMatchStarters: 9, hasMatchBaseline: true,
                                               bestClimb: .init(delta: 5, teamLabel: "Spirit"))
        #expect(result?.icon == "star.fill")
    }

    @Test func nothingGenuineGivesNoLine() {
        let result = PredictStreakLine.resolve(recent: [], bestMatchStarters: 0,
                                               hasMatchBaseline: false, bestClimb: nil)
        #expect(result == nil)
    }
}
