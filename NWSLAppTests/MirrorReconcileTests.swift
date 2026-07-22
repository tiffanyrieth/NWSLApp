//
//  MirrorReconcileTests.swift
//  NWSLAppTests
//
//  Sync set-logic + the stores' wholesale `replace…` setters. NOTE: ALERTS still use the
//  device-authoritative mirror (`TeamAlertSyncCoordinator`, device-wins + prune); FOLLOWS
//  moved to a RESTORE-ONLY launch reconcile (no launch prune — see FollowSyncCoordinator),
//  so the `replace…` setters below are exercised as the local side of a restore, not a prune.
//  Two layers under test:
//   1. The stores' wholesale `replace…` setters (the local side of the reconcile).
//   2. `TeamAlertSyncCoordinator.authoritativeOnSet` — the pure ALERTS set-logic that
//      decides the reconciled ON set (device-wins vs empty-local restore, and the
//      alerts ⊆ follows rule).
//

import Foundation
import Testing
@testable import NWSLApp

struct MirrorReconcileTests {

    private func isolatedDefaults(_ suite: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    // MARK: - Store-level replace (local side of the mirror)

    @Test func replaceEnabledIsAuthoritative() {
        let store = TeamAlertStore(defaults: isolatedDefaults("test.mirror.alerts.replace"))
        store.setAlertsEnabled(true, for: "A")
        store.setAlertsEnabled(true, for: "B")

        // Replace with a different set: A dropped, C added, B kept.
        store.replaceEnabled(["B", "C"])

        #expect(store.enabledTeamIDs == ["B", "C"])
        #expect(!store.alertsEnabled(for: "A"))
        #expect(store.enabledCount == 2)
    }

    @Test func replaceEnabledPersistsAcrossReload() {
        let suite = "test.mirror.alerts.persist"
        let defaults = isolatedDefaults(suite)
        let store = TeamAlertStore(defaults: defaults)
        store.setAlertsEnabled(true, for: "A")
        store.replaceEnabled(["X", "Y"])

        let reloaded = TeamAlertStore(defaults: defaults)
        #expect(reloaded.enabledTeamIDs == ["X", "Y"])
    }

    @Test func replaceFollowsIsAuthoritative() {
        let store = FollowingStore(defaults: isolatedDefaults("test.mirror.follows.replace"))
        store.replace(ids: ["A", "B", "C"])

        // Mirror down to a smaller set: B and C pruned, D added.
        store.replace(ids: ["A", "D"])

        #expect(store.followedIDs == ["A", "D"])
    }

    @Test func replaceDoesNotFireSyncSeam() {
        // The coordinator is the caller and reconciles the server itself; the replace
        // must NOT echo back through the change closure (which would re-push).
        let store = FollowingStore(defaults: isolatedDefaults("test.mirror.follows.noecho"))
        var fired = false
        store.onFollowsChanged = { _ in fired = true }
        store.replace(ids: ["A"])
        #expect(!fired)
    }

    @Test func completeOnboardingFiresOnceOnTheRealTransition() {
        // The coordinator hangs the first prune-capable reconcile off this hook, so it must fire
        // on the false→true transition and NOT again on a repeat call.
        let store = FollowingStore(defaults: isolatedDefaults("test.mirror.onboarded.hook"))
        var fires = 0
        store.onOnboardingCompleted = { fires += 1 }
        store.completeOnboarding()
        store.completeOnboarding()
        #expect(fires == 1)
    }

    // MARK: - Follows reconcile set-logic (UPWARD-ONLY, 2026-07-23)

    @Test func midOnboardingAddsButNeverPrunes() {
        // THE REGRESSION GUARD. Signing in from the alert-bell intercept mid-picker: the user has
        // tapped one club so far. That partial set must never look authoritative — adding is fine,
        // deleting is the "only the oldest follow survives" data-loss bug.
        let ops = FollowSyncCoordinator.resolveFollowOps(
            local: ["angelcity"],
            remote: ["spirit", "wave"],
            hasOnboarded: false)
        #expect(ops.add == ["angelcity"])
        #expect(ops.remove.isEmpty)
    }

    @Test func midOnboardingWithEmptyLocalIsANoOp() {
        // A fresh install that signs in before tapping anything: nothing to push, nothing to prune.
        // (The old code restored the server set here and skipped onboarding entirely.)
        let ops = FollowSyncCoordinator.resolveFollowOps(
            local: [], remote: ["spirit", "wave"], hasOnboarded: false)
        #expect(ops.add.isEmpty)
        #expect(ops.remove.isEmpty)
    }

    @Test func onboardedDeviceIsAuthoritativeBothWays() {
        // Post-onboarding the server is made to match the device exactly: "follow 16 then unfollow
        // back to 2" must leave the server holding 2.
        let ops = FollowSyncCoordinator.resolveFollowOps(
            local: ["spirit", "angelcity"],
            remote: ["spirit", "wave", "current", "thorns"],
            hasOnboarded: true)
        #expect(ops.add == ["angelcity"])
        #expect(ops.remove == ["wave", "current", "thorns"])
    }

    @Test func alreadyInSyncProducesNoWrites() {
        let ops = FollowSyncCoordinator.resolveFollowOps(
            local: ["spirit", "wave"], remote: ["spirit", "wave"], hasOnboarded: true)
        #expect(ops.add.isEmpty)
        #expect(ops.remove.isEmpty)
    }

    @Test func onboardedWithEmptyLocalClearsTheServer() {
        // Unfollowing everything is a legitimate state and must propagate — the device is the
        // source of truth, so an empty local set means an empty server set.
        let ops = FollowSyncCoordinator.resolveFollowOps(
            local: [], remote: ["spirit"], hasOnboarded: true)
        #expect(ops.add.isEmpty)
        #expect(ops.remove == ["spirit"])
    }

    // MARK: - Reconcile set-logic (device-wins / restore / alerts ⊆ follows)

    @Test func deviceWinsAndPrunesGhostAlerts() {
        // Local has an alert for "ghost" — a team that isn't followed (exactly the
        // live bug: row 15364 enabled with no matching follow). It must be dropped.
        let result = TeamAlertSyncCoordinator.authoritativeOnSet(
            localOn: ["spirit", "ghost"],
            followed: ["spirit", "angelcity"],
            restoreSource: [])
        #expect(result == ["spirit"])
    }

    @Test func deviceWinsIgnoresServerRestoreSource() {
        // With a non-empty local ON set the device is authoritative — the server's
        // (stale) enabled set is NOT pulled in, so old ghosts can't come back.
        let result = TeamAlertSyncCoordinator.authoritativeOnSet(
            localOn: ["spirit"],
            followed: ["spirit", "angelcity"],
            restoreSource: ["spirit", "wave", "current"])
        #expect(result == ["spirit"])
    }

    @Test func emptyLocalRestoresFromServer() {
        // Empty-local guardrail: a blank device restores the server's enabled set,
        // intersected with what it follows.
        let result = TeamAlertSyncCoordinator.authoritativeOnSet(
            localOn: [],
            followed: ["spirit", "angelcity"],
            restoreSource: ["spirit", "wave"])   // "wave" not followed → dropped
        #expect(result == ["spirit"])
    }

    @Test func deleteDiffIsEverythingNotKept() {
        // The prune step deletes every server row not in the authoritative set —
        // stale `true` ghosts AND leftover `false` clutter.
        let keep: Set<String> = ["spirit"]
        let allRemote: Set<String> = ["spirit", "wave", "current", "usa"]
        #expect(allRemote.subtracting(keep) == ["wave", "current", "usa"])
    }
}
