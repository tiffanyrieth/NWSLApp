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
        store.dayBefore = true; store.playerSpotlight = true; store.fanZoneRounds = true

        store.resetServerPushTypes()

        // Tier 2 → off.
        #expect(!store.kickoff)
        #expect(!store.goals)
        #expect(!store.halftime)
        #expect(!store.fullTime)
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

    /// Fresh-install defaults: only Tier-1 LOCAL types may start ON (they deliver
    /// signed-out). Every Tier-2 SERVER-PUSH type defaults OFF — they can't be
    /// delivered without an account, so defaulting them on for a first-run (likely
    /// signed-out) user would be a lie.
    @Test func freshDefaultsTier2OffTier1On() {
        let store = NotificationPreferencesStore(defaults: isolated("test.notif.defaults"))
        // Tier 2 (server push) → OFF.
        #expect(!store.kickoff)
        #expect(!store.goals)
        #expect(!store.halftime)
        #expect(!store.fullTime)
        // Tier 1 (local) + activity → ON.
        #expect(store.dayBefore)
        #expect(store.playerSpotlight)
        #expect(store.fanZoneRounds)
    }

    /// The hub-visited flag (gates the Teams row bell's first-tap "doorway"): false
    /// fresh, one-way to true via `markHubVisited`, idempotent, persists across reload.
    @Test func hubVisitedFlagPersistsAndIsIdempotent() {
        let suite = "test.notif.hubvisited"
        let defaults = isolated(suite)
        let store = NotificationPreferencesStore(defaults: defaults)
        #expect(!store.hubVisited)

        store.markHubVisited(isSignedIn: false)
        #expect(store.hubVisited)
        store.markHubVisited(isSignedIn: false)  // idempotent
        #expect(store.hubVisited)

        // Survives a store reload on the same suite.
        #expect(NotificationPreferencesStore(defaults: defaults).hubVisited)
    }

    /// Signed-OUT first hub visit upholds `Tier 2 ON ⟹ signed in`: the visit is
    /// recorded but every Tier-2 type stays OFF (only the gate can enable them).
    @Test func hubVisitSignedOutKeepsTier2Off() {
        let store = NotificationPreferencesStore(defaults: isolated("test.notif.visit.out"))
        store.markHubVisited(isSignedIn: false)
        #expect(store.hubVisited)
        #expect(!store.kickoff)
        #expect(!store.goals)
        #expect(!store.halftime)
        #expect(!store.fullTime)
        // Tier 1 untouched (still on by default).
        #expect(store.dayBefore)
        #expect(store.playerSpotlight)
    }

    /// Signed-IN first hub visit establishes the Tier-2 defaults ON (the live-match
    /// types), matching the spec's "signed in: default Tier 1 + Tier 2 all ON".
    @Test func hubVisitSignedInDefaultsTier2On() {
        let store = NotificationPreferencesStore(defaults: isolated("test.notif.visit.in"))
        store.markHubVisited(isSignedIn: true)
        #expect(store.hubVisited)
        #expect(store.kickoff)
        #expect(store.goals)
        #expect(store.halftime)
        #expect(store.fullTime)
    }

    /// `markHubVisited` only establishes Tier-2 defaults on the FIRST visit — a later
    /// signed-in visit must NOT silently re-enable types the user turned off.
    @Test func hubVisitDefaultsOnlyOnFirstVisit() {
        let store = NotificationPreferencesStore(defaults: isolated("test.notif.visit.once"))
        store.markHubVisited(isSignedIn: false)   // first visit, signed out → Tier 2 off
        store.markHubVisited(isSignedIn: true)    // later visit must not re-default
        #expect(!store.kickoff)
        #expect(!store.goals)
    }
}
