//
//  MirrorReconcileTests.swift
//  NWSLAppTests
//
//  The device-authoritative mirror sync model (replaces the old union-merge that
//  could only ever ADD, so stale server rows accumulated forever and the "N teams
//  with match alerts" footer inflated on sign-in). Two layers under test:
//   1. The stores' wholesale `replace…` setters (the local side of the mirror).
//   2. `TeamAlertSyncCoordinator.authoritativeOnSet` — the pure set-logic that
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
