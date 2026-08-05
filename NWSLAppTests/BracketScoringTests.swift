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
        // Pick the winner in 2 of 3 → 2 × 1 (Rd of 64 = 1pt).
        let picks = ["m0": "a0", "m1": "a1", "m2": "b2"]
        #expect(BracketScoring.correctCount(picks: picks, matchups: ms) == 2)
        #expect(BracketScoring.roundPoints(picks: picks, matchups: ms) == 2)
    }

    @Test func valueRisesInTiersByRound() {
        // One correct pick, same shape, different rounds → tiered points (1·1·2·2·3·3).
        func points(_ r: BracketRound) -> Int {
            BracketScoring.roundPoints(picks: ["m0": "a0"], matchups: matchups(round: r, count: 1))
        }
        #expect(points(.roundOf64) == 1)
        #expect(points(.roundOf32) == 1)
        #expect(points(.roundOf16) == 2)
        #expect(points(.quarterfinal) == 2)
        #expect(points(.semifinal) == 3)
        #expect(points(.final) == 3)
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
        // 32·1 + 16·1 + 8·2 + 4·2 + 2·3 + 1·3 = 81.
        #expect(BracketScoring.maxPoints(rounds: rounds) == 81)
    }

    @Test func smallerPoolStartsLaterAndScoresLess() {
        let rounds = BracketRound.rounds(forEntrants: 32)
        #expect(rounds.first == .roundOf32)
        #expect(rounds.count == 5)
        // 16·1 + 8·2 + 4·2 + 2·3 + 1·3 = 49.
        #expect(BracketScoring.maxPoints(rounds: rounds) == 49)
    }

    // MARK: - Qualifying rounds (large pools) — mirrors the proxy contract

    @Test func qualifyingRoundsAreOnePointThirtyTwoMatchups() {
        for q in [BracketRound.qualifying1, .qualifying2, .qualifying3, .qualifying4] {
            #expect(q.isQualifying)
            #expect(q.points == 1)
            #expect(q.matchupCount == 32)
        }
        #expect(BracketRound.qualifying1.title == "Qualifying 1")
        #expect(BracketRound.qualifying1.shortLabel == "Q1")
    }

    @Test func roundsPrependQualifyingForLargePools() {
        // 128 → 2 qualifying rounds then the full main bracket, in play order.
        #expect(BracketRound.rounds(forEntrants: 128) == [
            .qualifying1, .qualifying2, .roundOf64, .roundOf32, .roundOf16, .quarterfinal, .semifinal, .final,
        ])
        // 192 → 4 qualifying rounds; 96 → 1; >192 snaps to 192 (4 qualifying rounds).
        #expect(BracketRound.rounds(forEntrants: 96).first == .qualifying1)
        #expect(BracketRound.rounds(forEntrants: 96).filter(\.isQualifying).count == 1)
        #expect(BracketRound.rounds(forEntrants: 192).filter(\.isQualifying).count == 4)
        #expect(BracketRound.rounds(forEntrants: 256).filter(\.isQualifying).count == 4)
    }

    @Test func qualifyingSortsBeforeMainInPlayOrder() {
        #expect(BracketRound.qualifying1 < BracketRound.qualifying2)   // q1 first
        #expect(BracketRound.qualifying4 < BracketRound.roundOf64)     // qualifying before main
        #expect(BracketRound.roundOf64 < BracketRound.final)          // main: more entrants first
        // Sorting a shuffled set yields the canonical play order.
        let sorted = [BracketRound.final, .qualifying2, .roundOf64, .qualifying1].sorted()
        #expect(sorted == [.qualifying1, .qualifying2, .roundOf64, .final])
    }

    @Test func largePoolMaxIsRuleDerived() {
        // 128: q1+q2 (32·1·2) + 32·1 + 16·1 + 8·2 + 4·2 + 2·3 + 1·3 = 145.
        #expect(BracketScoring.maxPoints(rounds: BracketRound.rounds(forEntrants: 128)) == 145)
    }

    // MARK: - Result-card verdict copy

    /// THE BUG (owner-caught 2026-08-04): a MISS rendered "Solid — Trinity Rodman took it" in red, so the
    /// praise word "Solid" applied to a pick you got wrong. A miss must show the winner's ACTION alone.
    @Test func missDropsThePraiseAdjective() {
        let text = BracketScoring.verdictText(winnerPercent: 66, winnerName: "Trinity Rodman",
                                              roundPoints: 2, outcome: .missed)
        #expect(text == "Trinity Rodman took it")
        #expect(!text.contains("Solid"))
        #expect(!text.contains("—"))            // no leading "Adjective —"
        #expect(!text.contains("pts"))          // and no points on a miss
    }

    @Test func correctKeepsTheAdjectiveAndPoints() {
        let text = BracketScoring.verdictText(winnerPercent: 66, winnerName: "Casey Murphy",
                                              roundPoints: 1, outcome: .correct)
        #expect(text == "Solid — Casey Murphy took it  ·  +1 pts")
    }

    @Test func satOutKeepsTheAdjectiveWithoutPoints() {
        let text = BracketScoring.verdictText(winnerPercent: 66, winnerName: "Sam Coffey",
                                              roundPoints: 1, outcome: .satOut)
        #expect(text == "Solid — Sam Coffey took it")
    }

    /// The four margin buckets map to the right adjective + action verb; a miss carries the margin
    /// through the VERB alone (dominated / cruised through / took it / barely survived).
    @Test func marginBucketsMapToTheRightWords() {
        #expect(BracketScoring.verdictText(winnerPercent: 92, winnerName: "A", roundPoints: 1, outcome: .satOut) == "Runaway — A dominated")
        #expect(BracketScoring.verdictText(winnerPercent: 78, winnerName: "A", roundPoints: 1, outcome: .satOut) == "Comfortable — A cruised through")
        #expect(BracketScoring.verdictText(winnerPercent: 60, winnerName: "A", roundPoints: 1, outcome: .satOut) == "Solid — A took it")
        #expect(BracketScoring.verdictText(winnerPercent: 52, winnerName: "A", roundPoints: 1, outcome: .satOut) == "Nail-biter — A barely survived")
        // A miss at every margin is action-only (no adjective, no em-dash lead).
        for pct in [92, 78, 60, 52] {
            let miss = BracketScoring.verdictText(winnerPercent: pct, winnerName: "A", roundPoints: 1, outcome: .missed)
            #expect(!miss.contains("—"))
        }
    }
}
