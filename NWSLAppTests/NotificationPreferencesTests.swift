//
//  NotificationPreferencesTests.swift
//  NWSLAppTests
//
//  `resetServerPushTypes()` — the account-DELETE teardown (involuntary-sign-out fix: a plain
//  sign-out now PRESERVES stored Tier-2 toggles, display-gated on auth, so re-sign-in restores
//  them; only a deleted account wipes them). Tier-1 locals (day-before, Player Spotlight) keep
//  working signed-out and must survive the wipe.
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

    // MARK: - Reinstall restore (applyRestored)

    /// A restore adopts the saved row VERBATIM — including types the user deliberately turned OFF.
    /// A blanket re-cascade would silently undo those edits, which is why the restore isn't one.
    @Test func applyRestoredAdoptsRowVerbatim() {
        let store = NotificationPreferencesStore(defaults: isolated("test.notif.restore"))
        store.applyRestored(NotificationPreferencesSnapshot(
            dayBefore: true, lineupPosted: true, kickoff: true, goals: false, halftime: true,
            fullTime: true, substitutions: false, fanZoneRounds: true, playerSpotlight: false,
            liveActivitiesEnabled: true))

        #expect(store.dayBefore)
        #expect(store.lineupPosted)
        #expect(store.kickoff)
        #expect(!store.goals)            // deliberately off before the reinstall → still off
        #expect(store.halftime)
        #expect(store.fullTime)
        #expect(!store.substitutions)
        #expect(store.fanZoneRounds)
        #expect(!store.playerSpotlight)
        #expect(store.liveActivitiesEnabled)
    }

    /// After a restore the device HAS a considered state, so the first-bell cascade must not fire
    /// over it — otherwise turning on a second team would re-enable the type the user turned off.
    @Test func restoreSetsSentinelSoCascadeCannotOverwriteIt() {
        let store = NotificationPreferencesStore(defaults: isolated("test.notif.restore.sentinel"))
        #expect(!store.hasAppliedAlertDefaults)

        store.applyRestored(NotificationPreferencesSnapshot(
            dayBefore: true, lineupPosted: false, kickoff: true, goals: false, halftime: false,
            fullTime: false, substitutions: false, fanZoneRounds: false, playerSpotlight: false,
            liveActivitiesEnabled: false))
        #expect(store.hasAppliedAlertDefaults)

        store.applyMatchAlertDefaultsIfFirstTime()
        #expect(!store.goals)            // no-op: the restored selection stands
        #expect(!store.lineupPosted)
    }

    /// The restore persists like any other edit (a relaunch reads the restored values back).
    @Test func restorePersists() {
        let suite = "test.notif.restore.persist"
        let defaults = isolated(suite)
        NotificationPreferencesStore(defaults: defaults).applyRestored(
            NotificationPreferencesSnapshot(
                dayBefore: false, lineupPosted: false, kickoff: true, goals: true, halftime: false,
                fullTime: false, substitutions: false, fanZoneRounds: false, playerSpotlight: false,
                liveActivitiesEnabled: false))

        let reloaded = NotificationPreferencesStore(defaults: defaults)
        #expect(reloaded.kickoff)
        #expect(reloaded.goals)
        #expect(!reloaded.halftime)
        #expect(reloaded.hasAppliedAlertDefaults)
    }

    /// Account delete re-arms the restore/cascade: the sentinel is cleared alongside the toggles, so
    /// the next account's first bell tap cascades again instead of landing on a dead all-off state.
    @Test func resetClearsTheAppliedDefaultsSentinel() {
        let store = NotificationPreferencesStore(defaults: isolated("test.notif.reset.sentinel"))
        store.applyMatchAlertDefaultsIfFirstTime()
        #expect(store.hasAppliedAlertDefaults)

        store.resetServerPushTypes()
        #expect(!store.hasAppliedAlertDefaults)
    }
}
