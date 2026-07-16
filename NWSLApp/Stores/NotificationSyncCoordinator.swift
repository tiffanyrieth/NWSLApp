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
    /// Per-team alert intent, for the signed-out desync check ("any team's bell on counts as
    /// Tier-2 intent"). Optional so existing tests/previews that don't care keep constructing
    /// the coordinator unchanged.
    private let teamAlerts: TeamAlertStore?
    /// Injectable for Tier2SentinelTests; production uses .standard.
    private let defaults: UserDefaults

    /// Shadows of what we last sent the server, so we only push real deltas. Reset
    /// to nil on a sign-out / user switch so the next identity re-pushes from
    /// scratch.
    private var lastUploadedToken: String?
    private var lastPushedSnapshot: NotificationPreferencesSnapshot?
    private var lastUserID: UUID?

    init(
        auth: AuthStore,
        preferences: NotificationPreferencesStore,
        teamAlerts: TeamAlertStore? = nil,
        bridge: PushBridge = .shared,
        tokenService: DeviceTokenService = DeviceTokenService(),
        prefsService: NotificationPrefsSyncService = NotificationPrefsSyncService(),
        defaults: UserDefaults = .standard
    ) {
        self.auth = auth
        self.preferences = preferences
        self.teamAlerts = teamAlerts
        self.bridge = bridge
        self.tokenService = tokenService
        self.prefsService = prefsService
        self.defaults = defaults
    }

    /// Wire up sync. Call once, after `auth.restoreSession()`, from RootTabView.
    func start() {
        lastUserID = auth.userID
        sync()          // initial reconcile (covers an already-restored session)
        observe()
    }

    /// Force a reconcile — called from the launch/foreground registration reconcile to RETRY a
    /// previously-failed token upload (on failure the shadow isn't advanced, so `sync()` re-attempts)
    /// and to catch a token/session the observation may have missed.
    func resync() { sync() }

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
            // NOTE (involuntary-sign-out fix): the old `preferences.resetServerPushTypes()` on
            // sign-out is GONE — stored Tier-2 flags are now PRESERVED and merely display-gated
            // on auth (NotificationsView), so a re-sign-in restores the user's exact prior
            // selection with no server pull and no default-bundle re-cascade. The destructive
            // reset survives only in account-delete teardown (deleteAccount → local wipe).
        }

        // Tier 2 requires sign-in: nothing to mirror while signed out — but a signed-out state
        // with Tier-2 intent still stored is the involuntary-sign-out desync; reconcile the
        // sentinel EVERY pass here (not just on the transition edge, which a cold
        // launch-already-out never sees — that gap was half the original bug).
        guard let userID = newID else {
            reconcileSignedOutDesync()
            NotifTrace.shared.log("sync", .skip, "no signed-in user")
            return
        }

        if let token = bridge.deviceToken, token != lastUploadedToken {
            // Advance the shadow ONLY after the write succeeds — otherwise a failure (after a
            // pre-emptive shadow bump) could be skipped by a racing second sync and never retry.
            // The upsert is idempotent, so a rare double-send while one is in flight is harmless.
            Task {
                do {
                    try await tokenService.registerToken(token, userID: userID)
                    lastUploadedToken = token
                    NotifTrace.shared.log("device-upsert", .ok, "token=\(token.prefix(10))…")
                } catch {
                    Diagnostics.shared.record(.apiFailure, "notif registerToken: \(error.localizedDescription)")
                    NotifTrace.shared.log("device-upsert", .fail, error.localizedDescription)
                }
            }
        } else if bridge.deviceToken == nil {
            // The symptom we're chasing: signed in, but no APNs token has arrived to upload.
            NotifTrace.shared.log("sync", .skip, "signed in, no APNs token yet (not registered?)")
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

    // MARK: - Involuntary-sign-out desync sentinel

    /// Runs on every signed-out `sync()` pass. If the user still has Tier-2 intent stored
    /// (global types or any team's bell) and the sign-out wasn't deliberate, they're in the
    /// banned "opted in but structurally dead" state: set the persisted sentinel (RootTabView
    /// reads it for the auto-presented sign-in nudge) and emit telemetry — ONCE per detection,
    /// gated on the sentinel itself, so a signed-out user relaunching daily doesn't spam the
    /// Diagnostics sink. Sentinel lifecycle is documented on `SignOutSentinels`.
    private func reconcileSignedOutDesync() {
        guard !defaults.bool(forKey: SignOutSentinels.deliberateSignOut) else { return }
        guard !defaults.bool(forKey: SignOutSentinels.tier2WasOnAtSignOut) else { return }
        let snapshot = preferences.snapshot
        let teamsOn = teamAlerts?.enabledCount ?? 0
        guard snapshot.anyServerPushEnabled || teamsOn > 0 else { return }
        defaults.set(true, forKey: SignOutSentinels.tier2WasOnAtSignOut)
        Diagnostics.shared.record(.tier2SignedOutDesync,
            "signed out with alert intent: kickoff=\(snapshot.kickoff) goals=\(snapshot.goals) "
            + "ht=\(snapshot.halftime) ft=\(snapshot.fullTime) lineup=\(snapshot.lineupPosted) "
            + "la=\(snapshot.liveActivitiesEnabled) teams=\(teamsOn)")
    }
}
