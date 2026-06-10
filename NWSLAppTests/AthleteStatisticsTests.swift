//
//  AthleteStatisticsTests.swift
//  NWSLAppTests
//
//  Decode + mapping test for AthleteStatistics against a real captured ESPN Core
//  API response (NWSLAppTests/Fixtures/athlete-statistics.json — Emily Sams, Angel
//  City, 2026 Regular Season). Guards the defensive decoder, the category→field
//  flattening, and the roster-driven `isGoalkeeper` flag.
//
//  The fixture is read straight off disk via #filePath (like MatchSummaryTests),
//  so it needs no test-bundle resource membership.
//

import Foundation
import Testing
@testable import NWSLApp

struct AthleteStatisticsTests {

    /// Loads + decodes the captured stats fixture once per test.
    private func loadStats() throws -> AthleteStatistics {
        let fixture = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures/athlete-statistics.json")
        let data = try Data(contentsOf: fixture)
        return try JSONDecoder().decode(AthleteStatistics.self, from: data)
    }

    @Test func flattensCategoryAndStatNames() throws {
        let stats = try loadStats()
        let flat = stats.flattened()

        // Keys are "category.statName"; values are the captured numbers.
        #expect(flat["offensive.totalGoals"] == 1)
        #expect(flat["general.appearances"] == 11)
        #expect(flat["offensive.goalAssists"] == 1)
        // An unknown key is simply absent (no crash for missing stats).
        #expect(flat["offensive.notAStat"] == nil)
    }

    @Test func mapsOutfieldStatsToSeasonLine() throws {
        let line = try loadStats().playerSeasonStats(athleteID: "262615", isGoalkeeper: false)

        #expect(line.athleteID == "262615")
        #expect(line.appearances == 11)
        #expect(line.minutes == 963)
        #expect(line.goals == 1)
        #expect(line.assists == 1)
        #expect(line.shots == 7)
        #expect(line.isGoalkeeper == false)
    }

    @Test func isGoalkeeperIsCallerDrivenNotCategoryDriven() throws {
        // The same payload, mapped as a keeper, flips only the flag — the numbers
        // are unchanged. ESPN returns a goalKeeping category for outfielders too,
        // so the flag must come from the roster position, not category presence.
        let stats = try loadStats()
        let outfield = stats.playerSeasonStats(athleteID: "262615", isGoalkeeper: false)
        let keeper = stats.playerSeasonStats(athleteID: "262615", isGoalkeeper: true)

        #expect(outfield.isGoalkeeper == false)
        #expect(keeper.isGoalkeeper == true)
        #expect(keeper.goals == outfield.goals)
        #expect(keeper.appearances == outfield.appearances)
    }

    @Test func missingCategoriesMapToZero() throws {
        // A sparse payload (a player who barely featured): only `general` present,
        // no offensive/goalKeeping. Missing stats resolve to 0, not a decode error.
        let json = """
        { "splits": { "categories": [
            { "name": "general", "stats": [
                { "name": "appearances", "value": 2.0, "displayValue": "2" }
            ] }
        ] } }
        """
        let stats = try JSONDecoder().decode(AthleteStatistics.self, from: Data(json.utf8))
        let line = stats.playerSeasonStats(athleteID: "x", isGoalkeeper: false)

        #expect(line.appearances == 2)
        #expect(line.goals == 0)
        #expect(line.assists == 0)
        #expect(line.saves == 0)
        #expect(line.cleanSheets == 0)
    }
}
