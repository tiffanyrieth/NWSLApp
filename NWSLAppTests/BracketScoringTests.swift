//
//  BracketScoringTests.swift
//  NWSLAppTests
//
//  Covers the pure Bracket Battle scorer (BracketScoring): per-round escalating
//  points, the "N correct" count (only resolved matchups the user picked count),
//  and the rule-derived perfect-bracket maximum (546 for a full 64 pool — NOT the
//  mock's 468; see BracketScoring's note).
//

import Foundation
import Testing
@testable import NWSLApp

struct BracketScoringTests {

    // MARK: - Builders

    private func entrant(_ id: String) -> BracketEntrant {
        BracketEntrant(id: id, playerName: id, jerseyNumber: nil, teamAbbreviation: "WAS")
    }

    /// `count` matchups in `round`, ids "m0…"; each resolves with entrant "a{slot}"
    /// as the community winner over "b{slot}".
    private func matchups(round: BracketRound, count: Int) -> [BracketMatchup] {
        (0..<count).map { slot in
            BracketMatchup(
                id: "m\(slot)", round: round, slot: slot,
                entrantA: entrant("a\(slot)"), entrantB: entrant("b\(slot)"),
                communityWinnerID: "a\(slot)", splitAPercent: 60
            )
        }
    }

    // MARK: - Round points

    @Test func correctPickEarnsTheRoundValue() {
        let ms = matchups(round: .roundOf64, count: 3)
        // Pick the winner in 2 of 3 → 2 × 5.
        let picks = ["m0": "a0", "m1": "a1", "m2": "b2"]
        #expect(BracketScoring.correctCount(picks: picks, matchups: ms) == 2)
        #expect(BracketScoring.roundPoints(picks: picks, matchups: ms) == 10)
    }

    @Test func valueEscalatesByRound() {
        // One correct pick, same shape, different rounds → different points.
        func points(_ r: BracketRound) -> Int {
            BracketScoring.roundPoints(picks: ["m0": "a0"], matchups: matchups(round: r, count: 1))
        }
        #expect(points(.roundOf64) == 5)
        #expect(points(.roundOf32) == 8)
        #expect(points(.roundOf16) == 12)
        #expect(points(.quarterfinal) == 18)
        #expect(points(.semifinal) == 25)
        #expect(points(.final) == 40)
    }

    @Test func unresolvedOrUnpickedMatchupsScoreNothing() {
        var ms = matchups(round: .roundOf16, count: 2)
        ms[1].communityWinnerID = nil          // not yet tallied
        ms[1].splitAPercent = nil
        // Picked both, but only m0 is resolved → 1 correct × 12.
        let picks = ["m0": "a0", "m1": "a1"]
        #expect(BracketScoring.correctCount(picks: picks, matchups: ms) == 1)
        // No picks at all → 0.
        #expect(BracketScoring.roundPoints(picks: [:], matchups: ms) == 0)
    }

    // MARK: - Maximum

    @Test func perfectFullBracketMaxIsRuleDerived() {
        let rounds = BracketRound.rounds(forEntrants: 64)
        #expect(rounds.count == 6)
        // 32·5 + 16·8 + 8·12 + 4·18 + 2·25 + 1·40 = 546.
        #expect(BracketScoring.maxPoints(rounds: rounds) == 546)
    }

    @Test func smallerPoolStartsLaterAndScoresLess() {
        let rounds = BracketRound.rounds(forEntrants: 32)
        #expect(rounds.first == .roundOf32)
        #expect(rounds.count == 5)
        // 16·8 + 8·12 + 4·18 + 2·25 + 1·40 = 386.
        #expect(BracketScoring.maxPoints(rounds: rounds) == 386)
    }
}
