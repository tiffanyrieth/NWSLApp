//
//  KnowHerGameStoreTests.swift
//  NWSLAppTests
//
//  Know Her Game store — the post-completion-flow additions: week-agnostic edition reads (so a
//  LAST-WEEK player reads the right edition, not the current week) and the one-week "Last week"
//  retention rule. Pure/local — no network (the pool fetch is exercised in the sim).
//

import Foundation
import Testing
@testable import NWSLApp

struct KnowHerGameStoreTests {

    private func store() -> KnowHerGameStore {
        // Isolated defaults per test so banked scores don't leak across cases / the real app.
        let suite = UserDefaults(suiteName: "knowher.tests.\(UUID().uuidString)")!
        return KnowHerGameStore(defaults: suite)
    }

    @Test func editionKeyReadsAreWeekAgnostic() {
        let s = store()
        // Bank a score under LAST week's edition key.
        s.recordCompletion(editionKey: "2026-W28-WAS-317423", weekKey: "2026-W28", correct: 6, outOf: 10)

        // The raw edition read finds it regardless of the current week…
        #expect(s.score(editionKey: "2026-W28-WAS-317423") == 6)
        #expect(s.isPlayed(editionKey: "2026-W28-WAS-317423"))
        // …and a DIFFERENT edition (e.g. this week's) is untouched — the bug last-week reads would hit
        // if they keyed on the current week.
        #expect(s.score(editionKey: "2026-W29-WAS-317423") == nil)
        #expect(!s.isPlayed(editionKey: "2026-W29-WAS-317423"))
    }

    @Test func retainsPreviousEditionForOneOrTwoWeekGap() {
        // Kept: the immediately-prior BIWEEKLY edition (editions are 2 ISO weeks apart).
        #expect(KnowHerGameStore.retainsPreviousWeek(old: "2026-W27", new: "2026-W29"))
        // Kept: a 1-week gap too (cadence transition / legacy weekly data).
        #expect(KnowHerGameStore.retainsPreviousWeek(old: "2026-W28", new: "2026-W29"))
        // Kept across the year boundary (W52 → W01).
        #expect(KnowHerGameStore.retainsPreviousWeek(old: "2025-W52", new: "2026-W01"))
        // Dropped: a 3+ week gap (an edition was missed — app not opened in a while).
        #expect(!KnowHerGameStore.retainsPreviousWeek(old: "2026-W26", new: "2026-W29"))
        // Dropped: same edition (a reload, not a rotation).
        #expect(!KnowHerGameStore.retainsPreviousWeek(old: "2026-W29", new: "2026-W29"))
    }

    @Test func editionStreakContinuesAcrossBiweeklyGapAndResetsOnAMiss() {
        let s = store()
        s.recordCompletion(editionKey: "2026-W27-WAS-1", weekKey: "2026-W27", correct: 5, outOf: 10)
        #expect(s.weeklyStreak == 1)
        // Next biweekly edition (2 weeks later) → streak continues.
        s.recordCompletion(editionKey: "2026-W29-WAS-2", weekKey: "2026-W29", correct: 5, outOf: 10)
        #expect(s.weeklyStreak == 2)
        // A missed edition (4 weeks later = a 3+ week gap) → streak resets to 1.
        s.recordCompletion(editionKey: "2026-W33-WAS-3", weekKey: "2026-W33", correct: 5, outOf: 10)
        #expect(s.weeklyStreak == 1)
    }

    // MARK: - Picks (the community recap's "your pick" marks, 2026-07-29)

    @Test func picksAreBankedPerEditionAndReadBack() {
        let s = store()
        s.recordCompletion(editionKey: "2026-W29-WAS-1", weekKey: "2026-W29", correct: 2, outOf: 3,
                           picks: [0, 2, 1])
        #expect(s.picks(editionKey: "2026-W29-WAS-1") == [0, 2, 1])
        // An edition never played has no picks — the panel must render with no personal marks rather
        // than defaulting to option 0, which would silently claim an answer the user never gave.
        #expect(s.picks(editionKey: "2026-W29-HOU-9") == nil)
    }

    @Test func picksSurviveAReload() {
        let suite = UserDefaults(suiteName: "knowher.tests.\(UUID().uuidString)")!
        KnowHerGameStore(defaults: suite)
            .recordCompletion(editionKey: "2026-W29-WAS-1", weekKey: "2026-W29", correct: 1, outOf: 2,
                              picks: [3, 1])
        // A second store over the same defaults = the next app launch.
        #expect(KnowHerGameStore(defaults: suite).picks(editionKey: "2026-W29-WAS-1") == [3, 1])
    }

    @Test func completingANewEditionPrunesPicksOutsideTheRecapWindow() {
        let s = store()
        s.recordCompletion(editionKey: "2026-W25-WAS-1", weekKey: "2026-W25", correct: 1, outOf: 2, picks: [0, 1])
        s.recordCompletion(editionKey: "2026-W27-WAS-2", weekKey: "2026-W27", correct: 1, outOf: 2, picks: [1, 0])
        // W29 is the current edition; with no previousPool loaded the window is W29 alone, so both
        // older editions' picks go. Scores are untouched — they're season-long (Superfan total).
        s.recordCompletion(editionKey: "2026-W29-WAS-3", weekKey: "2026-W29", correct: 2, outOf: 2, picks: [1, 1])
        #expect(s.picks(editionKey: "2026-W29-WAS-3") == [1, 1])
        #expect(s.picks(editionKey: "2026-W27-WAS-2") == nil)
        #expect(s.picks(editionKey: "2026-W25-WAS-1") == nil)
        #expect(s.score(editionKey: "2026-W25-WAS-1") == 1)
    }

    @Test func pruningMatchesTheWholeWeekKeyNotAPrefix() {
        let s = store()
        // "2026-W3" is a PREFIX of "2026-W30" — pruning on the bare weekKey would keep W30's picks
        // alive on a W3 window (and vice versa). The prefix includes the trailing dash to prevent it.
        s.recordCompletion(editionKey: "2026-W30-WAS-1", weekKey: "2026-W30", correct: 1, outOf: 2, picks: [0, 1])
        s.recordCompletion(editionKey: "2026-W3-WAS-2", weekKey: "2026-W3", correct: 1, outOf: 2, picks: [1, 0])
        // Completing W3 leaves only W3's picks; W30's are outside the window.
        #expect(s.picks(editionKey: "2026-W3-WAS-2") == [1, 0])
        #expect(s.picks(editionKey: "2026-W30-WAS-1") == nil)
    }

    @Test func recordingTwiceDoesNotOverwriteTheFirstPicks() {
        let s = store()
        s.recordCompletion(editionKey: "2026-W29-WAS-1", weekKey: "2026-W29", correct: 2, outOf: 2, picks: [1, 1])
        // One attempt per edition: a re-record (retry, re-entry, double-tap) is a no-op for the score,
        // and must be one for the picks too — else a stale replay could rewrite the banked answers.
        s.recordCompletion(editionKey: "2026-W29-WAS-1", weekKey: "2026-W29", correct: 0, outOf: 2, picks: [0, 0])
        #expect(s.picks(editionKey: "2026-W29-WAS-1") == [1, 1])
        #expect(s.score(editionKey: "2026-W29-WAS-1") == 2)
    }

    // MARK: - Cross-device played-set restore (Gap 3)

    @Test func restorePlayedEditionsMarksPlayedWithScoreAndPicksByQuestionID() {
        let s = store()
        s.restorePlayedEditions([(editionKey: "2026-W29-WAS-317423", correct: 7, total: 10,
                                  picks: ["q1": 2, "q3": 0])])
        #expect(s.isPlayed(editionKey: "2026-W29-WAS-317423"))
        #expect(s.score(editionKey: "2026-W29-WAS-317423") == 7)
        // The recap looks picks up by question id (positional array is empty — this device didn't play).
        #expect(s.restoredPick(editionKey: "2026-W29-WAS-317423", questionID: "q1") == 2)
        #expect(s.restoredPick(editionKey: "2026-W29-WAS-317423", questionID: "q3") == 0)
        #expect(s.restoredPick(editionKey: "2026-W29-WAS-317423", questionID: "q2") == nil)
    }

    @Test func restorePlayedEditionsIsLocalWinsAndLeavesTheStreakAlone() {
        let s = store()
        s.recordCompletion(editionKey: "2026-W29-WAS-317423", weekKey: "2026-W29", correct: 9, outOf: 10,
                           picks: Array(repeating: 1, count: 10))
        let streakBefore = s.weeklyStreak
        // A server restore with a different score must NOT overwrite the real local play…
        s.restorePlayedEditions([(editionKey: "2026-W29-WAS-317423", correct: 3, total: 10, picks: ["q1": 0])])
        #expect(s.score(editionKey: "2026-W29-WAS-317423") == 9)
        #expect(s.restoredPick(editionKey: "2026-W29-WAS-317423", questionID: "q1") == nil, "no restored map for a local edition")
        // …and the streak is untouched (it rides the ProgressSnapshot rollup, not this restore).
        #expect(s.weeklyStreak == streakBefore)
    }

    @Test func restorePlayedEditionsBlocksReplayOnTheSecondDevice() {
        let s = store()
        s.restorePlayedEditions([(editionKey: "2026-W29-WAS-317423", correct: 5, total: 10, picks: [:])])
        // recordCompletion guards on scores[key]==nil, so a replay after a cross-device restore is a no-op.
        s.recordCompletion(editionKey: "2026-W29-WAS-317423", weekKey: "2026-W29", correct: 10, outOf: 10)
        #expect(s.score(editionKey: "2026-W29-WAS-317423") == 5)
    }
}
