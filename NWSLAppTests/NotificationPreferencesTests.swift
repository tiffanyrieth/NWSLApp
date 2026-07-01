//
//  NotificationPreferencesTests.swift
//  NWSLAppTests
//
//  `resetServerPushTypes()` — the sign-out teardown (QOL v2). Tier-2 alert types
//  can't be delivered without an account, so signing out turns them off; the Tier-1
//  locals (day-before, Player Spotlight) keep working signed-out and must survive.
//

import Foundation
import Testing
@testable import NWSLApp

struct NotificationPreferencesTests {

    private func isolated(_ suite: String) -> UserDefaults {
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    @Test func resetTurnsOffTier2KeepsTier1() {
        let store = NotificationPreferencesStore(defaults: isolated("test.notif.reset"))
        // Everything on to start.
        store.kickoff = true; store.goals = true; store.halftime = true; store.fullTime = true
        store.liveActivitiesEnabled = true
        store.dayBefore = true; store.playerSpotlight = true; store.fanZoneRounds = true

        store.resetServerPushTypes()

        // Tier 2 (incl. the V2 Live Activity) → off.
        #expect(!store.kickoff)
        #expect(!store.goals)
        #expect(!store.halftime)
        #expect(!store.fullTime)
        #expect(!store.liveActivitiesEnabled)
        // Tier 1 + activity → untouched (work without an account).
        #expect(store.dayBefore)
        #expect(store.playerSpotlight)
        #expect(store.fanZoneRounds)
    }

    @Test func resetPersists() {
        let suite = "test.notif.reset.persist"
        let defaults = isolated(suite)
        let store = NotificationPreferencesStore(defaults: defaults)
        store.kickoff = true
        store.resetServerPushTypes()

        // A fresh store on the same suite reads kickoff off.
        #expect(!NotificationPreferencesStore(defaults: defaults).kickoff)
    }

    /// Fresh-install defaults: PURE OPT-IN — every toggle starts OFF, nothing is auto-enabled. The user
    /// turns on exactly what they want (no dark-pattern default-ons).
    @Test func freshDefaultsAllOff() {
        let store = NotificationPreferencesStore(defaults: isolated("test.notif.defaults"))
        // Tier 2 (server push, incl. the V2 Live Activity) → OFF.
        #expect(!store.kickoff)
        #expect(!store.goals)
        #expect(!store.halftime)
        #expect(!store.fullTime)
        #expect(!store.liveActivitiesEnabled)
        // Tier 1 (local) + activity → also OFF now (opt-in).
        #expect(!store.dayBefore)
        #expect(!store.playerSpotlight)
        #expect(!store.fanZoneRounds)
    }
}
