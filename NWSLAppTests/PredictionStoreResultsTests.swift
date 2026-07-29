//
//  PredictionStoreResultsTests.swift
//  NWSLAppTests
//
//  The local state behind Predict the XI's show-a-result-once routing, and the submit deadline.
//
//  ⚠️ THE BUG THESE EXIST TO PREVENT: seen-tracking has to be PER FIXTURE. A single "last results
//  seen" flag — the obvious implementation, and what The Bracket can get away with because it has
//  one edition at a time — would mark all three of a weekend's results seen the moment the user
//  opened one of them. The other two reveals would be gone permanently, and the user would never
//  know they'd missed anything.
//

import Foundation
import Testing
@testable import NWSLApp

struct PredictionStoreResultsTests {

    private func freshStore(season: String = "2026") -> PredictionStore {
        let defaults = UserDefaults(suiteName: "test.predict.results.\(UUID().uuidString)")!
        return PredictionStore(defaults: defaults, season: season)
    }

    private func score(players: Int = 8, week: Int? = 12) -> PredictionScore {
        PredictionScore(correctPlayers: players, correctPositions: 0, formationCorrect: false,
                        exactScoreline: false, resultCorrect: false, perfectXI: false, soccerWeek: week)
    }

    private func completePrediction(_ fixtureID: String, team: String = "WAS",
                                    event: String = "e1") -> XIPrediction {
        XIPrediction(fixtureID: fixtureID, eventID: event, teamAbbreviation: team,
                     slots: Dictionary(uniqueKeysWithValues: (0...10).map { ($0, "a\($0)") }))
    }

    // MARK: - Seen tracking

    @Test func markingOneResultSeenLeavesTheOthersUnseen() {
        let store = freshStore()
        for id in ["e1-WAS", "e2-ANG", "e3-ORL"] {
            store.saveDraft(completePrediction(id))
            store.recordScore(score(), for: id)
        }
        store.markResultSeen(fixtureID: "e1-WAS")

        #expect(store.hasSeenResult(fixtureID: "e1-WAS"))
        #expect(!store.hasSeenResult(fixtureID: "e2-ANG"))
        #expect(!store.hasSeenResult(fixtureID: "e3-ORL"))
        #expect(Set(store.unseenScoredFixtureIDs(currentWeek: 12)) == ["e2-ANG", "e3-ORL"])
    }

    /// Insert-only, so a result can never become unseen and a reveal can never re-fire.
    @Test func seenIsMonotonic() {
        let store = freshStore()
        store.markResultSeen(fixtureID: "e1-WAS")
        store.markResultSeen(fixtureID: "e1-WAS")
        #expect(store.seenResultFixtureIDs == ["e1-WAS"])
    }

    @Test func seenSurvivesAStoreReload() {
        let defaults = UserDefaults(suiteName: "test.predict.reload.\(UUID().uuidString)")!
        let first = PredictionStore(defaults: defaults)
        first.markResultSeen(fixtureID: "e1-WAS")

        let reloaded = PredictionStore(defaults: defaults)
        #expect(reloaded.hasSeenResult(fixtureID: "e1-WAS"))
    }

    /// The results list only renders the current + previous soccer week, so an older result can't be
    /// opened and must not sit in the unseen queue forever pushing a route that goes nowhere.
    @Test func unseenExcludesResultsOutsideTheRenderWindow() {
        let store = freshStore()
        store.saveDraft(completePrediction("old-WAS"))
        store.recordScore(score(week: 3), for: "old-WAS")
        store.saveDraft(completePrediction("new-WAS"))
        store.recordScore(score(week: 12), for: "new-WAS")

        #expect(store.unseenScoredFixtureIDs(currentWeek: 12) == ["new-WAS"])
    }

    @Test func pruningDropsMarkersForUnrenderableResultsOnly() {
        let store = freshStore()
        store.saveDraft(completePrediction("old-WAS"))
        store.recordScore(score(week: 2), for: "old-WAS")
        store.saveDraft(completePrediction("new-WAS"))
        store.recordScore(score(week: 12), for: "new-WAS")
        store.markResultSeen(fixtureID: "old-WAS")
        store.markResultSeen(fixtureID: "new-WAS")

        store.pruneStaleMarkers(currentWeek: 12)
        #expect(!store.hasSeenResult(fixtureID: "old-WAS"))
        #expect(store.hasSeenResult(fixtureID: "new-WAS"))
    }

    /// An open fixture's upload marker must survive pruning — it hasn't been scored yet, so it isn't
    /// "old", and dropping it would re-send its picks.
    @Test func pruningKeepsMarkersForUnscoredFixtures() {
        let store = freshStore()
        store.saveDraft(completePrediction("open-WAS"))
        store.markPicksUploaded(fixtureID: "open-WAS")
        store.pruneStaleMarkers(currentWeek: 12)
        #expect(store.hasUploadedPicks(fixtureID: "open-WAS"))
    }

    // MARK: - Season bests

    @Test func seasonBestsOnlyEverRise() {
        let store = freshStore()
        store.mergeSeasonBests(PredictSeasonBests(season: "2026", bestMatchStarters: 9, bestRoundStarters: 20))
        store.mergeSeasonBests(PredictSeasonBests(season: "2026", bestMatchStarters: 4, bestRoundStarters: 30))
        #expect(store.seasonBests.bestMatchStarters == 9)
        #expect(store.seasonBests.bestRoundStarters == 30)
    }

    // MARK: - The submit deadline (logic gate #3 — gate the ACTION)

    /// The picker used to hold this check in its button. A picker left open across kickoff−2h could
    /// then still commit, and a "prediction" made after the lineup is public isn't one.
    @Test func submitIsRefusedAfterTheDeadline() {
        let store = freshStore()
        store.saveDraft(completePrediction("e1-WAS"))
        let deadline = Date(timeIntervalSince1970: 1_000_000)
        let after = deadline.addingTimeInterval(60)

        #expect(store.submit(fixtureID: "e1-WAS", before: deadline, now: after) == false)
        #expect(store.prediction(for: "e1-WAS")?.state == .draft)
    }

    @Test func submitSucceedsBeforeTheDeadlineAndIsOneWay() {
        let store = freshStore()
        store.saveDraft(completePrediction("e1-WAS"))
        let deadline = Date(timeIntervalSince1970: 1_000_000)
        let before = deadline.addingTimeInterval(-60)

        #expect(store.submit(fixtureID: "e1-WAS", before: deadline, now: before))
        #expect(store.prediction(for: "e1-WAS")?.state == .submitted)
        // A second call is a no-op, not a re-submit — the double-action guard's last line of defence.
        #expect(store.submit(fixtureID: "e1-WAS", before: deadline, now: before) == false)
        #expect(store.prediction(for: "e1-WAS")?.state == .submitted)
    }

    @Test func anIncompleteXICannotBeSubmitted() {
        let store = freshStore()
        var partial = completePrediction("e1-WAS")
        partial.slots.removeValue(forKey: 10)
        store.saveDraft(partial)
        let deadline = Date().addingTimeInterval(3600)
        #expect(store.submit(fixtureID: "e1-WAS", before: deadline) == false)
    }

    // MARK: - Account deletion

    @Test func accountDeletionClearsTheNewLocalState() {
        let store = freshStore()
        store.saveDraft(completePrediction("e1-WAS"))
        store.recordScore(score(), for: "e1-WAS")
        store.markResultSeen(fixtureID: "e1-WAS")
        store.markPicksUploaded(fixtureID: "e1-WAS")
        store.mergeSeasonBests(PredictSeasonBests(season: "2026", bestMatchStarters: 9, bestRoundStarters: 20))

        store.resetForAccountDeletion()

        #expect(store.seenResultFixtureIDs.isEmpty)
        #expect(store.uploadedPickFixtureIDs.isEmpty)
        #expect(store.seasonBests.bestMatchStarters == 0)
    }
}
