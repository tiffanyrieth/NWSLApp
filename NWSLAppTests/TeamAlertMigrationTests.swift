//
//  TeamAlertMigrationTests.swift
//  NWSLAppTests
//
//  The one-time seed of per-team match alerts from the old GLOBAL Match Day toggles
//  (QOL v2). Per-team is ON/OFF now. On upgrade from 0.3.9, a followed team gets
//  alerts ON only if the user actually had any match-day alert on globally (the
//  owner's rule) — so nobody who had alerts loses them, and nobody who had none
//  suddenly starts buzzing. Runs exactly once (sentinel-guarded). Isolated
//  UserDefaults suite per test.
//

import Foundation
import Testing
@testable import NWSLApp

struct TeamAlertMigrationTests {

    /// A fresh, isolated UserDefaults so tests never touch the real app prefs or each
    /// other. Cleared up front in case a prior run left the suite populated.
    private func isolatedDefaults(_ suite: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func snapshot(
        dayBefore: Bool = false, kickoff: Bool = false, goals: Bool = false,
        halftime: Bool = false, fullTime: Bool = false
    ) -> NotificationPreferencesSnapshot {
        NotificationPreferencesSnapshot(
            dayBefore: dayBefore, lineupPosted: false, kickoff: kickoff,
            goals: goals, halftime: halftime, fullTime: fullTime,
            substitutions: false, fanZoneRounds: true, playerSpotlight: true
        )
    }

    @Test func seedsFollowedTeamsWhenHadGlobalAlerts() {
        let store = TeamAlertStore(defaults: isolatedDefaults("test.alerts.seed"))

        // Had kickoff on globally → followed teams inherit alerts ON.
        store.migrateFromGlobalIfNeeded(global: snapshot(kickoff: true), followedIDs: ["A", "B"])

        #expect(store.alertsEnabled(for: "A"))
        #expect(store.alertsEnabled(for: "B"))
        #expect(store.enabledCount == 2)
    }

    @Test func doesNotSeedWhenNoGlobalAlerts() {
        let store = TeamAlertStore(defaults: isolatedDefaults("test.alerts.noseed"))

        // All match-day toggles off → nobody is seeded (the owner's rule).
        store.migrateFromGlobalIfNeeded(global: snapshot(), followedIDs: ["A", "B"])

        #expect(!store.alertsEnabled(for: "A"))
        #expect(store.enabledCount == 0)
    }

    @Test func newlyFollowedTeamsDefaultOff() {
        let store = TeamAlertStore(defaults: isolatedDefaults("test.alerts.optin"))

        store.migrateFromGlobalIfNeeded(global: snapshot(goals: true), followedIDs: ["A"])

        // "C" wasn't followed at migration → off.
        #expect(!store.alertsEnabled(for: "C"))
    }

    @Test func migrationRunsOnceAndDoesNotClobberLaterEdits() {
        let store = TeamAlertStore(defaults: isolatedDefaults("test.alerts.idempotent"))

        store.migrateFromGlobalIfNeeded(global: snapshot(dayBefore: true), followedIDs: ["A"])
        #expect(store.alertsEnabled(for: "A"))

        // User turns A off; a second migration must NOT re-seed it on.
        store.setAlertsEnabled(false, for: "A")
        store.migrateFromGlobalIfNeeded(global: snapshot(dayBefore: true), followedIDs: ["A"])
        #expect(!store.alertsEnabled(for: "A"))
    }

    @Test func migrationPersistsAcrossStoreReload() {
        let suite = "test.alerts.persist"
        let defaults = isolatedDefaults(suite)
        TeamAlertStore(defaults: defaults)
            .migrateFromGlobalIfNeeded(global: snapshot(fullTime: true), followedIDs: ["A"])

        // A fresh store on the same suite reads the persisted enabled set.
        let reloaded = TeamAlertStore(defaults: defaults)
        #expect(reloaded.alertsEnabled(for: "A"))
    }

    @Test func setAndToggleRoundTrip() {
        let store = TeamAlertStore(defaults: isolatedDefaults("test.alerts.toggle"))
        #expect(!store.alertsEnabled(for: "A"))
        store.toggle(for: "A")
        #expect(store.alertsEnabled(for: "A"))
        store.toggle(for: "A")
        #expect(!store.alertsEnabled(for: "A"))
        #expect(store.enabledCount == 0)
    }
}
