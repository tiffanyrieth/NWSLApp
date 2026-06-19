//
//  NotificationSyncCoordinator.swift
//  NWSLApp
//
//  The Tier-2 (server push) twin of FollowSyncCoordinator: the ONLY place the
//  device token + notification preferences are mirrored to Supabase. AuthStore and
//  NotificationPreferencesStore stay pure and ignorant of the network; this
//  coordinator depends on both and on PushBridge (the APNs token sink). Nothing
//  depends on it — RootTabView just holds it alive and calls `start()`, exactly
//  like the follow coordinator and the local NotificationScheduler.
//
//  Its job is to keep the server's two facts current so the match-watcher Worker
//  can act on them:
//   1. The user's APNs device token (`device_tokens`) — who to push to.
//   2. The nine notification toggles (`notification_preferences`) — whether to.
//
//  All network steps are best-effort: the local toggles and Tier-1 scheduling work
//  regardless; a failed push just reconciles again on the next change or launch.
//  Tier 2 requires sign-in, so everything no-ops while signed out (the token simply
//  isn't uploaded until there's a user to key it to).
//
//  Observation, not the `onPreferenceChanged` closure: that single seam is already
//  taken by NotificationScheduler (Tier 1). So, like NotificationScheduler watches
//  `following.followedIDs` directly, we watch `preferences.snapshot` (+ the auth id
//  and the APNs token) via withObservationTracking.
//
//  `@MainActor` because it reads SwiftUI-observed state and uses
//  withObservationTracking, which must register on the actor that mutates it.
//

import Foundation
import Observation

@MainActor
@Observable
final class NotificationSyncCoordinator {
    private let auth: AuthStore
    private let preferences: NotificationPreferencesStore
    private let bridge: PushBridge
    private let tokenService: DeviceTokenService
    private let prefsService: NotificationPrefsSyncService

    /// Shadows of what we last sent the server, so we only push real deltas. Reset
    /// to nil on a sign-out / user switch so the next identity re-pushes from
    /// scratch.
    private var lastUploadedToken: String?
    private var lastPushedSnapshot: NotificationPreferencesSnapshot?
    private var lastUserID: UUID?

    init(
        auth: AuthStore,
        preferences: NotificationPreferencesStore,
        bridge: PushBridge = .shared,
        tokenService: DeviceTokenService = DeviceTokenService(),
        prefsService: NotificationPrefsSyncService = NotificationPrefsSyncService()
    ) {
        self.auth = auth
        self.preferences = preferences
        self.bridge = bridge
        self.tokenService = tokenService
        self.prefsService = prefsService
    }

    /// Wire up sync. Call once, after `auth.restoreSession()`, from RootTabView.
    func start() {
        lastUserID = auth.userID
        sync()          // initial reconcile (covers an already-restored session)
        observe()
    }

    // MARK: - Observation

    /// Re-arming observation of the three inputs: the signed-in user, the APNs
    /// token (delivered asynchronously by AppDelegate → PushBridge), and the nine
    /// toggles. Any change runs `sync()`, which is idempotent.
    private func observe() {
        withObservationTracking {
            _ = auth.userID
            _ = bridge.deviceToken
            _ = preferences.snapshot
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.sync()
                self.observe()
            }
        }
    }

    // MARK: - Sync

    /// Reconcile server state with local. Idempotent: pushes only what changed, and
    /// no-ops entirely while signed out. Handles the sign-out / user-switch
    /// transition first (remove the old token, reset shadows), then uploads the
    /// current token and preferences for the signed-in user.
    private func sync() {
        let newID = auth.userID

        // Identity transition: a sign-out or a switch to a different user.
        if newID != lastUserID {
            // A real sign-out (had a user, now none) — not the initial signed-out
            // launch (lastUserID already nil).
            let signedOut = newID == nil && lastUserID != nil
            if let oldID = lastUserID, let token = bridge.deviceToken {
                // Detach this device's token from the account we're leaving, so a
                // shared phone stops getting the previous user's alerts.
                Task {
                    do { try await tokenService.removeToken(token, userID: oldID) }
                    catch { Diagnostics.shared.record(.apiFailure, "notif removeToken: \(error.localizedDescription)") }
                }
            }
            lastUploadedToken = nil
            lastPushedSnapshot = nil
            lastUserID = newID
            if signedOut {
                // Tier-2 types can't be delivered without an account (the token is
                // detached above), so don't leave them showing "on". Tier-1 locals
                // stay. The user re-enables Tier-2 from the hub after signing back
                // in — gate-free, since they're signed in. (This mutates the snapshot
                // the observer watches; the re-fired sync() skips this branch — the
                // ids now match — so there's no loop.)
                preferences.resetServerPushTypes()
            }
        }

        // Tier 2 requires sign-in: nothing to mirror while signed out.
        guard let userID = newID else { return }

        if let token = bridge.deviceToken, token != lastUploadedToken {
            // Advance the shadow ONLY after the write succeeds — otherwise a failure (after a
            // pre-emptive shadow bump) could be skipped by a racing second sync and never retry.
            // The upsert is idempotent, so a rare double-send while one is in flight is harmless.
            Task {
                do {
                    try await tokenService.registerToken(token, userID: userID)
                    lastUploadedToken = token
                } catch {
                    Diagnostics.shared.record(.apiFailure, "notif registerToken: \(error.localizedDescription)")
                }
            }
        }

        let snapshot = preferences.snapshot
        if snapshot != lastPushedSnapshot {
            Task {
                do {
                    try await prefsService.pushPreferences(snapshot, userID: userID)
                    lastPushedSnapshot = snapshot
                } catch {
                    Diagnostics.shared.record(.apiFailure, "notif pushPreferences: \(error.localizedDescription)")
                }
            }
        }
    }
}
