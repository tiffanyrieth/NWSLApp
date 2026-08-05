//
//  PlayersLearnedStoreTests.swift
//  NWSLAppTests
//
//  The Superfan "players learned" collection store — dedupes by athlete keeping the BEST score, orders
//  newest-first, season-scoped. Pure over an injected UserDefaults.
//

import Foundation
import Testing
@testable import NWSLApp

struct PlayersLearnedStoreTests {

    private func isolated(_ suite: String) -> UserDefaults {
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    private func player(_ id: String, _ name: String, best: Int, at: Double) -> LearnedPlayer {
        LearnedPlayer(athleteId: id, name: name, teamAbbr: "WAS", bestCorrect: best, outOf: 5, learnedAt: at)
    }

    @Test func recordsDedupesKeepingBestScoreAndOrdersNewestFirst() {
        let d = isolated("test.playerslearned.1")
        PlayersLearnedStore.record(player("1", "Andi Sullivan", best: 3, at: 100), season: 2026, defaults: d)
        PlayersLearnedStore.record(player("2", "Trinity Rodman", best: 5, at: 200), season: 2026, defaults: d)
        #expect(PlayersLearnedStore.count(season: 2026, defaults: d) == 2)
        // Newest-learned first.
        #expect(PlayersLearnedStore.load(season: 2026, defaults: d).first?.athleteId == "2")

        // Replaying a player is idempotent on the COUNT and only RAISES her best score.
        PlayersLearnedStore.record(player("1", "Andi Sullivan", best: 4, at: 300), season: 2026, defaults: d)
        #expect(PlayersLearnedStore.count(season: 2026, defaults: d) == 2)
        let andi = { PlayersLearnedStore.load(season: 2026, defaults: d).first { $0.athleteId == "1" }! }
        #expect(andi().bestCorrect == 4)

        // A worse replay never lowers the stamp.
        PlayersLearnedStore.record(player("1", "Andi Sullivan", best: 1, at: 400), season: 2026, defaults: d)
        #expect(andi().bestCorrect == 4)
    }

    @Test func seasonsAreSeparate() {
        let d = isolated("test.playerslearned.2")
        PlayersLearnedStore.record(player("1", "A", best: 3, at: 100), season: 2026, defaults: d)
        #expect(PlayersLearnedStore.count(season: 2026, defaults: d) == 1)
        #expect(PlayersLearnedStore.count(season: 2027, defaults: d) == 0)
    }
}
