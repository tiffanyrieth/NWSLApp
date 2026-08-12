//
//  TeamStatsDecodeTests.swift
//  NWSLAppTests
//
//  The bundled `/team-stats` proxy path (#10 — the team-page stats-burst fix): the route returns every
//  athlete's FULL flattened season stats in one call, and the app builds `PlayerSeasonStats` from that flat
//  map via `PlayerSeasonStats(flat:)`. These tests guard (1) that the flat init is byte-identical to the
//  per-athlete `AthleteStatistics.playerSeasonStats` path — so the leaders board + player pages look the same
//  whether served bundled or via the outage fallback — and (2) that the `TeamStatsResponse` JSON decodes.
//

import Foundation
import Testing
@testable import NWSLApp

struct TeamStatsDecodeTests {

    private func loadStats() throws -> AthleteStatistics {
        let fixture = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures/athlete-statistics.json")
        return try JSONDecoder().decode(AthleteStatistics.self, from: try Data(contentsOf: fixture))
    }

    @Test func flatInitIsIdenticalToThePerAthletePath() throws {
        // The bundled path and the fallback path MUST agree. Both derive from the same flattened dict, so
        // building from `flattened()` via the flat init equals the per-athlete mapping exactly.
        let stats = try loadStats()
        let viaFallback = stats.playerSeasonStats(athleteID: "262615", isGoalkeeper: false)
        let viaBundle = PlayerSeasonStats(flat: stats.flattened(), athleteID: "262615", isGoalkeeper: false)

        #expect(viaBundle.appearances == viaFallback.appearances)
        #expect(viaBundle.minutes == viaFallback.minutes)
        #expect(viaBundle.goals == viaFallback.goals)
        #expect(viaBundle.assists == viaFallback.assists)
        #expect(viaBundle.shots == viaFallback.shots)
        #expect(viaBundle.saves == viaFallback.saves)
        #expect(viaBundle.cleanSheets == viaFallback.cleanSheets)
        #expect(viaBundle.goalsAgainst == viaFallback.goalsAgainst)
        #expect(viaBundle.all == viaFallback.all)                 // full set preserved → same detail sections
        #expect(viaBundle.seasonSections.count == viaFallback.seasonSections.count)
    }

    @Test func decodesTheBundledResponseAndBuildsSeasonLines() throws {
        // The exact proxy shape: { team, year, players: [{ athleteId, stats: {"category.statName": value} }] }.
        let json = """
        { "team": "20905", "year": 2026, "players": [
            { "athleteId": "262615", "stats": {
                "general.appearances": 11, "general.minutes": 963,
                "offensive.totalGoals": 1, "offensive.goalAssists": 1, "offensive.totalShots": 7
            } },
            { "athleteId": "999", "stats": {
                "general.appearances": 8, "goalKeeping.saves": 20, "goalKeeping.cleanSheet": 3, "goalKeeping.goalsConceded": 6
            } }
        ] }
        """
        let response = try JSONDecoder().decode(TeamStatsResponse.self, from: Data(json.utf8))
        #expect(response.players.count == 2)

        // Outfielder — the isGoalkeeper flag is caller-supplied (from the roster), not in the stats.
        let outfield = PlayerSeasonStats(flat: response.players[0].stats, athleteID: response.players[0].athleteId, isGoalkeeper: false)
        #expect(outfield.athleteID == "262615")
        #expect(outfield.appearances == 11)
        #expect(outfield.minutes == 963)
        #expect(outfield.goals == 1)
        #expect(outfield.assists == 1)
        #expect(outfield.shots == 7)
        #expect(outfield.isGoalkeeper == false)

        // Keeper — same builder, keeper fields populated, flag from the caller.
        let keeper = PlayerSeasonStats(flat: response.players[1].stats, athleteID: response.players[1].athleteId, isGoalkeeper: true)
        #expect(keeper.saves == 20)
        #expect(keeper.cleanSheets == 3)
        #expect(keeper.goalsAgainst == 6)
        #expect(keeper.isGoalkeeper == true)
    }

    @Test func missingStatsResolveToZeroNotADecodeError() throws {
        // A sparse player (barely featured): only a couple of keys. Missing headline stats → 0, no crash.
        let json = #"{ "team": "1", "year": 2026, "players": [ { "athleteId": "x", "stats": { "general.appearances": 2 } } ] }"#
        let response = try JSONDecoder().decode(TeamStatsResponse.self, from: Data(json.utf8))
        let line = PlayerSeasonStats(flat: response.players[0].stats, athleteID: "x", isGoalkeeper: false)
        #expect(line.appearances == 2)
        #expect(line.goals == 0)
        #expect(line.saves == 0)
    }
}
