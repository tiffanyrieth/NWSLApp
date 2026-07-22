//
//  ProgressSyncTests.swift
//  NWSLAppTests
//
//  The Fan Zone progress-restore merge + the stores' restore mutations. The merge is MONOTONIC
//  (fan-zone logic-gate #5: a reinstall/stale row can never lower a fresher count) and each streak
//  travels as a PAIR with its last-completed marker — the side that played more recently owns it.
//

import Foundation
import Testing
@testable import NWSLApp

struct ProgressSyncTests {

    private func snapshot(
        season: String = "2026",
        tCorrect: Int = 0, tAnswered: Int = 0, tBest: Int = 0, tSeason: Int = 0,
        tStreak: Int = 0, tLastRound: Int = 0,
        kPoints: Int = 0, kEditions: Int = 0, kStreak: Int = 0, kBest: Int = 0, kLastWeek: String? = nil
    ) -> ProgressSnapshot {
        ProgressSnapshot(season: season,
                         triviaLifetimeCorrect: tCorrect, triviaLifetimeAnswered: tAnswered,
                         triviaBestStreak: tBest, triviaSeasonCorrect: tSeason,
                         triviaRoundStreak: tStreak, triviaLastRound: tLastRound,
                         khgSeasonPoints: kPoints, khgEditionsPlayed: kEditions,
                         khgWeekStreak: kStreak, khgBestWeekStreak: kBest, khgLastWeek: kLastWeek)
    }

    // MARK: - Merge monotonicity

    @Test func freshInstallTakesTheServerSide() {
        // The replacement-phone case: local is all zeros, server has the season.
        let merged = ProgressSnapshot.merge(
            local: snapshot(),
            server: snapshot(tCorrect: 55, tAnswered: 80, tBest: 6, tSeason: 30, tStreak: 4,
                             tLastRound: 9, kPoints: 41, kEditions: 5, kStreak: 3, kBest: 4,
                             kLastWeek: "2026-W28"))
        #expect(merged.triviaLifetimeCorrect == 55)
        #expect(merged.triviaRoundStreak == 4)
        #expect(merged.triviaLastRound == 9)
        #expect(merged.khgSeasonPoints == 41)
        #expect(merged.khgWeekStreak == 3)
        #expect(merged.khgLastWeek == "2026-W28")
    }

    @Test func aStaleServerRowNeverLowersLocalCounters() {
        // Local kept playing after the last upload — the older server row must not regress anything.
        let merged = ProgressSnapshot.merge(
            local: snapshot(tCorrect: 60, tAnswered: 90, tBest: 7, tSeason: 35, tStreak: 5, tLastRound: 10,
                            kPoints: 50, kEditions: 6, kStreak: 4, kBest: 4, kLastWeek: "2026-W30"),
            server: snapshot(tCorrect: 55, tAnswered: 80, tBest: 6, tSeason: 30, tStreak: 4, tLastRound: 9,
                             kPoints: 41, kEditions: 5, kStreak: 3, kBest: 4, kLastWeek: "2026-W28"))
        #expect(merged.triviaLifetimeCorrect == 60)
        #expect(merged.triviaRoundStreak == 5, "local played round 10 — its streak is the live one")
        #expect(merged.khgSeasonPoints == 50)
        #expect(merged.khgLastWeek == "2026-W30")
    }

    @Test func streaksTravelAsAPairWithTheirMarker() {
        // Server has the RECENT play (round 10) but a short streak; local has an old long streak
        // (round 6). Taking max of each field separately would fabricate a long live streak — the
        // pair rule takes the server's (streak 1, round 10) together.
        let merged = ProgressSnapshot.merge(
            local: snapshot(tStreak: 8, tLastRound: 6),
            server: snapshot(tStreak: 1, tLastRound: 10))
        #expect(merged.triviaRoundStreak == 1)
        #expect(merged.triviaLastRound == 10)
    }

    @Test func bestStreaksAreIndependentOfTheMarkerPair() {
        // The PERSONAL BEST is a plaque, not a live value — max both sides regardless of recency.
        let merged = ProgressSnapshot.merge(
            local: snapshot(tBest: 3, tLastRound: 12, kBest: 2),
            server: snapshot(tBest: 9, tLastRound: 4, kBest: 5, kLastWeek: "2026-W10"))
        #expect(merged.triviaBestStreak == 9)
        #expect(merged.khgBestWeekStreak == 5)
    }

    // MARK: - Store restore mutations

    private func isolatedDefaults(_ suite: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func triviaRestoreOnAFreshDeviceAdoptsServerProgress() {
        let store = TriviaStore(defaults: isolatedDefaults("test.progress.trivia.fresh"))
        store.restoreProgress(lifetimeCorrect: 55, lifetimeAnswered: 80, bestStreak: 6,
                              seasonCorrect: 30, roundStreak: 4, lastRound: 9)
        #expect(store.totalCorrect == 55)
        #expect(store.streak == 4)
        #expect(store.lastCompletedRound == 9)
        #expect(store.hasEverPlayed)

        // The next completion (round 10) must CONTINUE the restored streak — this is the
        // owner's whole scenario: replacement phone, season carries on seamlessly.
        store.recordCompletion(round: 10, editionKey: "2026-R10", correct: 7, outOf: 10, picks: [])
        #expect(store.streak == 5)
    }

    @Test func triviaRestoreNeverRegressesAFresherDevice() {
        let store = TriviaStore(defaults: isolatedDefaults("test.progress.trivia.fresher"))
        store.recordCompletion(round: 10, editionKey: "2026-R10", correct: 8, outOf: 10, picks: [])
        store.restoreProgress(lifetimeCorrect: 3, lifetimeAnswered: 10, bestStreak: 1,
                              seasonCorrect: 3, roundStreak: 1, lastRound: 4)
        #expect(store.totalCorrect == 8, "stale restore can't lower the live count")
        #expect(store.lastCompletedRound == 10)
        #expect(store.streak == 1)
    }

    @Test func knowHerRestoreFloorsSeasonReadsWithoutFabricatingEditions() {
        let store = KnowHerGameStore(defaults: isolatedDefaults("test.progress.khg.fresh"))
        store.restoreProgress(year: 2026, points: 41, editions: 5,
                              weekStreak: 3, bestWeekStreak: 4, lastWeek: "2026-W28")
        #expect(store.seasonPoints(year: 2026) == 41)
        #expect(store.seasonEditionsPlayed(year: 2026) == 5)
        #expect(store.playedInSeason(year: 2026))
        #expect(store.seasonPoints(year: 2025) == 0, "a baseline never leaks across seasons")
        #expect(store.weeklyStreak == 3)
    }

    @Test func knowHerLocalPlayOverBaselineDoesNotDoubleCount() {
        // The baseline is a FLOOR (max), not an addend: local completions that were already part of
        // the server total must not stack on top of it.
        let store = KnowHerGameStore(defaults: isolatedDefaults("test.progress.khg.floor"))
        store.recordCompletion(editionKey: "2026-W29-WAS-317423", weekKey: "2026-W29", correct: 8)
        store.restoreProgress(year: 2026, points: 8, editions: 1,
                              weekStreak: 1, bestWeekStreak: 1, lastWeek: "2026-W29")
        #expect(store.seasonPoints(year: 2026) == 8, "8 locally + baseline 8 (same play) = 8, not 16")
        #expect(store.seasonEditionsPlayed(year: 2026) == 1)

        // NEW play after the restore grows past the floor.
        store.recordCompletion(editionKey: "2026-W31-WAS-999", weekKey: "2026-W31", correct: 6)
        #expect(store.seasonPoints(year: 2026) == 14)
        #expect(store.seasonEditionsPlayed(year: 2026) == 2)
    }
}
