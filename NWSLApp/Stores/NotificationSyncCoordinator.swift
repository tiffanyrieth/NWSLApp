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

    /// Reinstall-restore bookkeeping (see `restorePreferences`). `nil` = not yet attempted for the
    /// current identity, which blocks the prefs push **while `needsRestore`** — a fresh install's
    /// all-off snapshot must never reach the server before we've read the user's saved row (that
    /// push is what erased it). Set to the user id once the attempt finishes — success or a benign
    /// "nothing to restore". A FAILED fetch leaves it nil so the next `resync()` (every foreground)
    /// retries; the push stays blocked meanwhile, which costs nothing because local is all-off.
    private var restoredForUserID: UUID?
    /// Guards against two overlapping restore Tasks (sync() is re-entrant via observation).
    private var restoreInFlight = false

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

    /// Re-arming observation of the four inputs: the signed-in user, the APNs
    /// token (delivered asynchronously by AppDelegate → PushBridge), the nine
    /// toggles, and the per-team bells. Any change runs `sync()`, which is idempotent.
    ///
    /// The bells are watched for the restore invariant only: TeamAlertSyncCoordinator restores them
    /// on its OWN async Task, so they can land after our restore pass — observing them lets the
    /// "a bell is on ⇒ the bundle has been applied" check re-run the moment they arrive, whichever
    /// coordinator finishes first.
    private func observe() {
        withObservationTracking {
            _ = auth.userID
            _ = bridge.deviceToken
            _ = preferences.snapshot
            _ = teamAlerts?.enabledTeamIDs
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
            restoredForUserID = nil     // a new identity re-arms the reinstall restore
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

        // REINSTALL RESTORE, before any prefs push — but ONLY on a device that has nothing to lose.
        // The push is gated exclusively while `needsRestore` (a fresh install: no local choices, no
        // sentinel), because that is the one state where pushing would overwrite the user's saved row
        // with an all-off snapshot (the bug: bells restored ON, every alert type OFF, nothing fires).
        //
        // ⚠️ The gate MUST stay this narrow. A first cut gated EVERY push behind "the restore attempt
        // finished for this identity", which silently blocked preference syncing for a whole session
        // on a device that had real toggles (sim-caught 2026-07-22: the user's newly-enabled alert
        // types never reached Supabase, so the next reinstall had nothing to restore). A device that
        // already has state is device-authoritative — it must always be free to push.
        if needsRestore {
            guard restoredForUserID == userID else {
                restorePreferences(for: userID)
                return
            }
        } else if restoredForUserID != userID {
            // Traced once per identity: the restore was never even attempted because this device
            // already had state. Without this line a skipped restore is invisible — the exact gap
            // that made the 2026-07-22 sim runs unreadable.
            restoredForUserID = userID
            NotifTrace.shared.log("prefs-restore", .skip,
                "local has state — device-authoritative (local=\(Self.describe(preferences.snapshot)) "
                + "sentinel=\(preferences.hasAppliedAlertDefaults))")
        }

        // The bells may have arrived after the restore pass (separate coordinator, separate Task) —
        // re-check the invariant on every later pass. No-ops once the sentinel is set.
        cascadeIfTeamBellsOnWithoutDefaults()

        let snapshot = preferences.snapshot
        if snapshot != lastPushedSnapshot {
            Task {
                do {
                    try await prefsService.pushPreferences(snapshot, userID: userID)
                    lastPushedSnapshot = snapshot
                    // Traced like `device-upsert`: without this, "did my toggles actually reach the
                    // server?" is unanswerable from the field, and a push that never RAN looks
                    // identical to one that succeeded (the 2026-07-22 blocked-push bug).
                    NotifTrace.shared.log("prefs-push", .ok,
                        "ko=\(snapshot.kickoff) goals=\(snapshot.goals) ht=\(snapshot.halftime) "
                        + "ft=\(snapshot.fullTime) lineup=\(snapshot.lineupPosted) "
                        + "day=\(snapshot.dayBefore) la=\(snapshot.liveActivitiesEnabled)")
                } catch {
                    Diagnostics.shared.record(.apiFailure, "notif pushPreferences: \(error.localizedDescription)")
                    NotifTrace.shared.log("prefs-push", .fail, error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Reinstall restore (the alert types)

    /// Is this device in the ONE state a restore is for — a fresh install that has never made a
    /// notification choice (no cascade, no manual edit, no earlier restore)? Everything else is
    /// device-authoritative: no pull, and never a gated push. Cheap + local, so it's safe to read on
    /// every sync pass.
    private var needsRestore: Bool {
        !preferences.hasAppliedAlertDefaults && !preferences.snapshot.anyEnabled
    }

    /// What to do with the server's saved prefs row on a given device state. Pure + `nonisolated` so
    /// the whole decision is unit-testable without Supabase — same idiom as
    /// `TeamAlertSyncCoordinator.authoritativeOnSet` / `FollowSyncCoordinator.resolveFollowOps`.
    enum RestoreDecision: Equatable {
        /// Device-authoritative: leave the local toggles exactly as they are. (Named `noRestore`,
        /// not `none`, so `== .none` at a call site can't be read as `Optional.none`.)
        case noRestore
        /// Adopt the saved row verbatim (a deliberately-OFF type stays off).
        case restore(NotificationPreferencesSnapshot)
        /// Nothing worth restoring, but a team bell is on — cascade the default bundle, because a
        /// bell with every type off is the banned "on but nothing fires" state.
        case cascade
    }

    nonisolated static func decideRestore(
        hasAppliedDefaults: Bool,
        local: NotificationPreferencesSnapshot,
        server: NotificationPreferencesSnapshot?,
        teamBellsOn: Int
    ) -> RestoreDecision {
        // This install has already made a choice (a bell cascade, a manual edit, or an earlier
        // restore) — the device owns intent, exactly as it does across a sign-out / sign-in.
        guard !hasAppliedDefaults, !local.anyEnabled else { return .noRestore }
        // A saved row only counts if it actually says something. An all-off row (or the row this
        // very bug left behind) falls through to the bell invariant below.
        if let server, server.anyEnabled { return .restore(server) }
        return teamBellsOn > 0 ? .cascade : .noRestore
    }

    /// Compact one-line rendering of a snapshot for the trace (`-` = nil, no saved row).
    nonisolated static func describe(_ s: NotificationPreferencesSnapshot?) -> String {
        guard let s else { return "-" }
        func f(_ label: String, _ on: Bool) -> String { on ? label : "" }
        let flags = f("ko", s.kickoff) + f("go", s.goals) + f("ht", s.halftime) + f("ft", s.fullTime)
            + f("ln", s.lineupPosted) + f("dy", s.dayBefore) + f("la", s.liveActivitiesEnabled)
        return flags.isEmpty ? "none" : flags
    }

    /// Fetch the saved row once per identity and apply `decideRestore`. Marks the identity restored
    /// (unblocking the prefs push) only when the attempt completes; a network/RLS failure records
    /// Diagnostics and leaves it unmarked so the next foreground `resync()` retries — and, crucially,
    /// so a fresh install's all-off snapshot is never pushed over the saved row in the meantime.
    private func restorePreferences(for userID: UUID) {
        guard !restoreInFlight else { return }
        restoreInFlight = true
        Task {
            defer { restoreInFlight = false }
            do {
                let server = try await prefsService.fetchPreferences(userID: userID)
                // The one line that makes a restore diagnosable in the field: what the SERVER holds,
                // what the DEVICE holds, and the inputs to the decision. Without it, "restored",
                // "cascaded" and "nothing there" are indistinguishable after the fact.
                NotifTrace.shared.log("prefs-fetch", .ok,
                    "server=\(Self.describe(server)) local=\(Self.describe(preferences.snapshot)) "
                    + "sentinel=\(preferences.hasAppliedAlertDefaults) bells=\(teamAlerts?.enabledCount ?? -1)")
                let decision = Self.decideRestore(
                    hasAppliedDefaults: preferences.hasAppliedAlertDefaults,
                    local: preferences.snapshot,
                    server: server,
                    teamBellsOn: teamAlerts?.enabledCount ?? 0
                )
                switch decision {
                case .noRestore:
                    NotifTrace.shared.log("prefs-restore", .skip, "device-authoritative or nothing to restore")
                case .restore(let snapshot):
                    preferences.applyRestored(snapshot)
                    // We just adopted the server's own row — don't echo it straight back up.
                    lastPushedSnapshot = snapshot
                    NotifTrace.shared.log("prefs-restore", .ok, "restored saved alert types")
                case .cascade:
                    preferences.applyMatchAlertDefaultsIfFirstTime()
                    NotifTrace.shared.log("prefs-restore", .ok, "no saved types + bells on → cascaded bundle")
                }
                restoredForUserID = userID
                sync()      // resume the normal path (token upload + push) now that we're unblocked
            } catch {
                Diagnostics.shared.record(.apiFailure, "notif fetchPreferences: \(error.localizedDescription)")
                NotifTrace.shared.log("prefs-restore", .fail, error.localizedDescription)
            }
        }
    }

    /// The standing invariant: **a team bell on ⇒ the alert-type bundle has been applied at least
    /// once.** Only fires when the bundle has NEVER been applied on this device, so a bell restored
    /// from the server can't land in the "on but every type off" state — and a user who later turns
    /// types off keeps their edits (the sentinel is set by then).
    private func cascadeIfTeamBellsOnWithoutDefaults() {
        guard !preferences.hasAppliedAlertDefaults, (teamAlerts?.enabledCount ?? 0) > 0 else { return }
        // Never cascade OVER a selection the user already made. Signing in by tapping "Match updates"
        // enables those columns without the sentinel — blanket-enabling Goals/Lineups/Live Activities
        // on top of that would be the app choosing for them. Only the genuinely broken state (a bell
        // on with NO server-push type) gets the bundle. `anyServerPushEnabled` (not `anyEnabled`) so
        // the onboarding bell — which sets only the Tier-1 day-before reminder, by design — still
        // cascades the full bundle at sign-in, exactly as documented.
        guard !preferences.snapshot.anyServerPushEnabled else { return }
        preferences.applyMatchAlertDefaultsIfFirstTime()
        NotifTrace.shared.log("prefs-restore", .ok, "bells arrived after restore → cascaded bundle")
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
