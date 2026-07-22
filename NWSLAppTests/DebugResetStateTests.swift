//
//  DebugResetStateTests.swift
//  NWSLAppTests
//
//  `-resetOnboarding` (NWSLAppApp.init) simulates a brand-new install. Beyond
//  clearing follows + onboarding, it now also wipes Fan Zone game progress so the
//  reset is a true fresh user, not just fresh follows. These tests pin each store's
//  `debugResetState` against the EXACT production path: write progress via the
//  store's public API, reset the suite, then reload a fresh store and assert it
//  reads default/empty.
//
//  Why a unit test and not a sim run: the reset writes cleared sentinels and the
//  store reads them back IN THE SAME PROCESS (App.init → store.init), which
//  UserDefaults guarantees. A `simctl defaults` round-trip can't verify this —
//  seeding from an external process creates a cfprefsd split-brain where the app
//  and `defaults` see diverged views. An isolated in-process suite is the faithful
//  check, and it also guards against key-name drift between a store and its reset.
//

import Foundation
import Testing
@testable import NWSLApp

struct DebugResetStateTests {

    /// A fresh, isolated UserDefaults so a test never touches the real app prefs or
    /// another test. Cleared up front in case a prior run left the suite populated.
    private func isolatedDefaults(_ suite: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    // MARK: - Trivia (scalar keys → 0, dict keys → empty Data())

    @Test func triviaResetClearsProgress() {
        let defaults = isolatedDefaults("test.reset.trivia")
        let store = TriviaStore(defaults: defaults)
        store.recordCompletion(round: 8, editionKey: "2026-R08", correct: 7, outOf: 10,
                               picks: [0, 1, 2, 3, 0, 1, 2, 3, 0, 1])
        // Sanity: progress is actually present before the reset.
        #expect(store.bestStreak > 0)
        #expect(store.totalAnswered == 10)
        #expect(store.isPlayed(editionKey: "2026-R08"))

        TriviaStore.debugResetState(defaults: defaults)

        let reloaded = TriviaStore(defaults: defaults)
        #expect(reloaded.streak == 0)
        #expect(reloaded.bestStreak == 0)
        #expect(reloaded.totalCorrect == 0)
        #expect(reloaded.totalAnswered == 0)
        #expect(reloaded.lastCompletedRound == 0)
        // The empty-Data() sentinel decodes back to empty maps → "never played".
        #expect(!reloaded.isPlayed(editionKey: "2026-R08"))
        #expect(reloaded.picks(editionKey: "2026-R08") == nil)
    }

    // MARK: - Predict the XI (JSON keys → empty Data(), seasonPoints → 0)

    @Test func predictResetClearsProgress() {
        let defaults = isolatedDefaults("test.reset.predict")
        let store = PredictionStore(defaults: defaults)
        store.saveDraft(XIPrediction(fixtureID: "e1-WAS", eventID: "e1", teamAbbreviation: "WAS"))
        store.recordScore(
            PredictionScore(correctPlayers: 11, correctPositions: 0, formationCorrect: false,
                            exactScoreline: false, resultCorrect: false, perfectXI: false),
            for: "e1-WAS"
        )
        #expect(store.seasonPoints > 0)
        #expect(store.hasPredicted)

        PredictionStore.debugResetState(defaults: defaults)

        let reloaded = PredictionStore(defaults: defaults)
        // The empty-Data() sentinel must decode back to an empty map (the whole point
        // of the try?-decode fallback, not a stale or crashing read).
        #expect(reloaded.predictions.isEmpty)
        #expect(reloaded.scores.isEmpty)
        #expect(!reloaded.hasPredicted)
        #expect(reloaded.seasonPoints == 0)
        #expect(reloaded.scoredTeams.isEmpty)
        #expect(reloaded.points(forTeam: "WAS") == 0)
    }

    // MARK: - Team alerts (array key → []) — Part B Bug 2

    @Test func teamAlertsResetClearsEnabledTeams() {
        let defaults = isolatedDefaults("test.reset.teamAlerts")
        let store = TeamAlertStore(defaults: defaults)
        store.setAlertsEnabled(true, for: "21422")
        store.setAlertsEnabled(true, for: "22187")
        // Sanity: the phantom "N teams with match alerts" footer reads this count.
        #expect(store.enabledCount == 2)

        TeamAlertStore.debugResetState(defaults: defaults)

        let reloaded = TeamAlertStore(defaults: defaults)
        // The whole point of Bug 2: zero teams followed ⟹ zero alerts after reset.
        #expect(reloaded.enabledCount == 0)
        #expect(!reloaded.alertsEnabled(for: "21422"))
        #expect(reloaded.teamsWithAlerts().isEmpty)
    }

    // MARK: - Bracket Battle (JSON keys → empty Data(), editionID → "")

    @Test func bracketResetClearsProgress() {
        let defaults = isolatedDefaults("test.reset.bracket")
        let store = BracketStore(defaults: defaults)
        store.setPick(matchupID: "m1", entrantID: "x", round: .roundOf64)
        store.recordScore(10, for: .roundOf64)
        store.submit(round: .roundOf64)
        #expect(store.hasPlayed)
        #expect(store.points == 10)

        BracketStore.debugResetState(defaults: defaults)

        let reloaded = BracketStore(defaults: defaults)
        #expect(reloaded.picksByRound.isEmpty)
        #expect(!reloaded.hasPlayed)
        #expect(reloaded.submittedRounds.isEmpty)
        #expect(reloaded.roundScores.isEmpty)
        #expect(reloaded.points == 0)
    }
}
