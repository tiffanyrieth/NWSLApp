//
//  TriviaStoreRoundTests.swift
//  NWSLAppTests
//
//  TriviaStore under the biweekly ROUND model: the round-gate, round-streak adjacency,
//  the owner's current+previous retention prune, and completion idempotency (Fan Zone
//  logic-gate items 1/3/5: no double-count, no replay, reinstall-safe aggregates).
//

import Foundation
import Testing
@testable import NWSLApp

struct TriviaStoreRoundTests {

    private func isolatedDefaults(_ suite: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func key(_ round: Int) -> String { FanZoneCadence.editionKey(round: round, seasonYear: 2026) }

    private func complete(_ store: TriviaStore, round: Int, correct: Int = 7) {
        store.recordCompletion(round: round, editionKey: key(round), correct: correct, outOf: 10,
                               picks: Array(repeating: 0, count: 10))
    }

    // MARK: - The round gate (logic-gate #1/#3: idempotent, no replay)

    @Test func completingARoundTwiceIsANoOp() {
        let store = TriviaStore(defaults: isolatedDefaults("test.trivia.round.idempotent"))
        complete(store, round: 5, correct: 7)
        complete(store, round: 5, correct: 10)   // a replay attempt with a better score

        #expect(store.score(editionKey: key(5)) == 7, "the first banked score stands")
        #expect(store.totalAnswered == 10, "no double-count")
        #expect(store.streak == 1, "no streak farming")
    }

    // MARK: - Round streak

    @Test func streakContinuesOnAdjacentRoundsAndResetsOnAGap() {
        let store = TriviaStore(defaults: isolatedDefaults("test.trivia.round.streak"))
        complete(store, round: 3)
        complete(store, round: 4)
        #expect(store.streak == 2)
        #expect(store.bestStreak == 2)

        complete(store, round: 6)   // skipped round 5
        #expect(store.streak == 1, "a missed round restarts the streak")
        #expect(store.bestStreak == 2, "the personal best survives")
    }

    @Test func firstEverRoundStartsTheStreakAtOne() {
        let store = TriviaStore(defaults: isolatedDefaults("test.trivia.round.first"))
        complete(store, round: 12)
        #expect(store.streak == 1)
    }

    // MARK: - Retention (owner rule: current + previous round only)

    @Test func onlyTheLastTwoRoundsSurvive() {
        let store = TriviaStore(defaults: isolatedDefaults("test.trivia.round.retention"))
        complete(store, round: 1, correct: 5)
        complete(store, round: 2, correct: 6)
        complete(store, round: 3, correct: 7)

        #expect(store.score(editionKey: key(1)) == nil, "round 1 pruned")
        #expect(store.picks(editionKey: key(1)) == nil)
        #expect(store.score(editionKey: key(2)) == 6)
        #expect(store.score(editionKey: key(3)) == 7)
        // Aggregates are NOT history — pruning must never touch them.
        #expect(store.totalCorrect == 18)
        #expect(store.totalAnswered == 30)
        #expect(store.streak == 3)
    }

    @Test func retentionPrunesAcrossASeasonBoundary() {
        // Zero-padded keys sort correctly across years ("2027-R01" > "2026-R26") — the prune
        // must keep the two chronologically-latest, not the two lexically-odd ones.
        let store = TriviaStore(defaults: isolatedDefaults("test.trivia.round.season"))
        store.recordCompletion(round: 25, editionKey: "2026-R25", correct: 5, outOf: 10, picks: [])
        store.recordCompletion(round: 26, editionKey: "2026-R26", correct: 6, outOf: 10, picks: [])
        store.recordCompletion(round: 1, editionKey: "2027-R01", correct: 7, outOf: 10, picks: [])

        #expect(store.score(editionKey: "2026-R25") == nil)
        #expect(store.score(editionKey: "2026-R26") == 6)
        #expect(store.score(editionKey: "2027-R01") == 7)
    }

    // MARK: - Persistence round-trip

    @Test func roundStateSurvivesReload() {
        let suite = "test.trivia.round.reload"
        let defaults = isolatedDefaults(suite)
        let store = TriviaStore(defaults: defaults)
        store.recordCompletion(round: 8, editionKey: key(8), correct: 9, outOf: 10,
                               picks: [1, 2, 3, 0, 1, 2, 3, 0, 1, 2])

        let reloaded = TriviaStore(defaults: defaults)
        #expect(reloaded.score(editionKey: key(8)) == 9)
        #expect(reloaded.picks(editionKey: key(8)) == [1, 2, 3, 0, 1, 2, 3, 0, 1, 2])
        #expect(reloaded.lastCompletedRound == 8)
        #expect(reloaded.streak == 1)
    }

    // MARK: - Migration from the daily model

    @Test func dailyLifetimeCountersCarryOverAndBestStreakIsKept() {
        let suite = "test.trivia.round.migration"
        let defaults = isolatedDefaults(suite)
        // Simulate a device that played under the DAILY model: old keys present.
        defaults.set(9, forKey: "trivia.streak")            // old day-streak (must NOT carry)
        defaults.set(12, forKey: "trivia.bestStreak")       // personal best (carries numerically)
        defaults.set(55, forKey: "trivia.totalCorrect")
        defaults.set(80, forKey: "trivia.totalAnswered")
        defaults.set(30, forKey: "trivia.seasonCorrect")
        defaults.set(2026, forKey: "trivia.counterSeason")

        let store = TriviaStore(defaults: defaults)
        #expect(store.streak == 0, "a day-streak must not masquerade as a round-streak")
        #expect(store.bestStreak == 12)
        #expect(store.totalCorrect == 55)
        #expect(store.totalAnswered == 80)
        #expect(store.seasonCorrect == 30)
        #expect(store.hasEverPlayed)
    }
}
