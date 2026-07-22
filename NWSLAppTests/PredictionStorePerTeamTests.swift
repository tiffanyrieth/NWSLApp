//
//  PredictionStorePerTeamTests.swift
//  NWSLAppTests
//
//  The Predict the XI leaderboard is PER-TEAM (you're ranked among fans of your own
//  club). That hinges on `PredictionStore.points(forTeam:)` splitting the season
//  total by the team each scored prediction belongs to. These tests pin that
//  grouping so a Spirit fan's points never leak into another club's standings.
//

import Testing
import Foundation
@testable import NWSLApp

struct PredictionStorePerTeamTests {
    /// An isolated store so a test never reads/writes the shared simulator defaults.
    private func freshStore() -> PredictionStore {
        let defaults = UserDefaults(suiteName: "test.predict.\(UUID().uuidString)")!
        return PredictionStore(defaults: defaults)
    }

    /// A score worth exactly `players * 3` points (only the players category set).
    private func score(players: Int, week: Int? = nil) -> PredictionScore {
        PredictionScore(correctPlayers: players, correctPositions: 0,
                        formationCorrect: false, exactScoreline: false,
                        resultCorrect: false, perfectXI: false, soccerWeek: week)
    }

    // MARK: - ROUND (soccer-week) scoping — the comp arena's second clock

    @Test func weekPointsSumATwoGameWeekAndExcludeOtherWeeks() {
        // The owner's rule: Spirit playing Wednesday AND Saturday → both fixtures land in ONE round.
        let store = freshStore()
        store.saveDraft(XIPrediction(fixtureID: "e1-WAS", eventID: "e1", teamAbbreviation: "WAS"))
        store.recordScore(score(players: 10, week: 12), for: "e1-WAS")  // 30 pts, Wed
        store.saveDraft(XIPrediction(fixtureID: "e2-WAS", eventID: "e2", teamAbbreviation: "WAS"))
        store.recordScore(score(players: 5, week: 12), for: "e2-WAS")   // 15 pts, Sat
        store.saveDraft(XIPrediction(fixtureID: "e3-WAS", eventID: "e3", teamAbbreviation: "WAS"))
        store.recordScore(score(players: 11, week: 13), for: "e3-WAS")  // 33 pts, next week

        #expect(store.points(forTeam: "WAS", week: 12) == 45)
        #expect(store.points(forTeam: "WAS", week: 13) == 33)
        #expect(store.points(forTeam: "WAS", week: 11) == 0)
        #expect(store.points(forTeam: "WAS") == 78, "the season clock is untouched by week scoping")
        #expect(store.latestScoredWeek(forTeam: "WAS") == 13)
    }

    @Test func preRoundClockScoresStayOutOfRoundSumsButInTheSeason() {
        // Scores persisted before soccerWeek existed decode as nil — their week is unknowable, so
        // they contribute to NO round board but still count toward the season totals.
        let store = freshStore()
        store.saveDraft(XIPrediction(fixtureID: "e1-WAS", eventID: "e1", teamAbbreviation: "WAS"))
        store.recordScore(score(players: 8), for: "e1-WAS")             // legacy, no week
        store.saveDraft(XIPrediction(fixtureID: "e2-WAS", eventID: "e2", teamAbbreviation: "WAS"))
        store.recordScore(score(players: 4, week: 9), for: "e2-WAS")

        #expect(store.points(forTeam: "WAS", week: 9) == 12)
        #expect(store.points(forTeam: "WAS") == 36)
        #expect(store.latestScoredWeek(forTeam: "WAS") == 9)
    }

    @Test func pointsAreScopedPerTeam() {
        let store = freshStore()
        store.saveDraft(XIPrediction(fixtureID: "e1-WAS", eventID: "e1", teamAbbreviation: "WAS"))
        store.recordScore(score(players: 11), for: "e1-WAS")   // 33 pts
        store.saveDraft(XIPrediction(fixtureID: "e2-ORL", eventID: "e2", teamAbbreviation: "ORL"))
        store.recordScore(score(players: 5), for: "e2-ORL")    // 15 pts

        #expect(store.points(forTeam: "WAS") == 33)
        #expect(store.points(forTeam: "ORL") == 15)
        #expect(store.points(forTeam: "KC") == 0)              // no predictions for KC
        #expect(store.seasonPoints == 48)                      // cross-team total is the sum
        #expect(store.scoredTeams == ["WAS", "ORL"])
    }

    @Test func bothSidesOfOneMatchScoreIndependently() {
        // Following both teams in a match yields two fixtures keyed by the same
        // event but different team abbreviations — they must not cross-contaminate.
        let store = freshStore()
        store.saveDraft(XIPrediction(fixtureID: "e9-WAS", eventID: "e9", teamAbbreviation: "WAS"))
        store.recordScore(score(players: 4), for: "e9-WAS")    // 12 pts
        store.saveDraft(XIPrediction(fixtureID: "e9-NJ", eventID: "e9", teamAbbreviation: "NJ"))
        store.recordScore(score(players: 7), for: "e9-NJ")     // 21 pts

        #expect(store.points(forTeam: "WAS") == 12)
        #expect(store.points(forTeam: "NJ") == 21)
        #expect(store.scoredTeams == ["WAS", "NJ"])
    }
}
