//
//  TeamAlertSyncCoordinator.swift
//  NWSLApp
//
//  The ONLY place per-team alert prefs are mirrored to Supabase — the per-team twin
//  of NotificationSyncCoordinator. TeamAlertStore + FollowingStore + AuthStore stay
//  pure and network-ignorant; this coordinator depends on all three. Nothing depends
//  on it — RootTabView holds it alive and calls `start()`, like the other coordinators.
//
//  It does two jobs:
//   1. Mirror every per-team prefs edit up to `team_alert_preferences` (via the
//      store's `onAlertPrefsChanged` seam — unclaimed, unlike FollowingStore's
//      single closure). No-ops while signed out; reconciles on the next sign-in.
//   2. Enforce "alerts require following": when a team leaves the followed set, clear
//      its alerts. FollowingStore.onFollowsChanged is already owned by
//      FollowSyncCoordinator, so — like NotificationScheduler — we watch
//      `following.followedIDs` directly via withObservationTracking and diff it.
//
//  ⚠️ SYNC DIRECTION IS ONE-WAY — UP (owner ruling 2026-08-03, `docs/data-sync.md`).
//  Which teams you alert on is a CHOICE, and choices never come back down: a reinstall is a clean
//  slate, and NOT re-enabling a bell is a real signal, not data loss. Supabase holds a copy solely so
//  the match-watcher knows who to push to. This coordinator therefore converges the SERVER to the
//  DEVICE and never the reverse.
//  There USED to be a restore branch here (2026-07-22) that pulled the server's rows down onto an
//  empty device. Its own comment claimed it "mirrored the follows contract" — true for exactly one
//  day, until follows became upward-only on 2026-07-23, after which the two silently disagreed. That
//  is what made a fresh reinstall turn a bell back on the moment you tapped FOLLOW. Do not reinstate
//  it; the detailed alert TYPES still restore (NotificationSyncCoordinator), the team choice does not.
//
//  All network steps are best-effort; the local toggles work regardless.
//
//  `@MainActor` because it reads SwiftUI-observed stores and uses
//  withObservationTracking, which must register on the actor that mutates them.
//

import Foundation
import Observation

@MainActor
@Observable
final class TeamAlertSyncCoordinator {
    private let auth: AuthStore
    private let alerts: TeamAlertStore
    private let following: FollowingStore
    private let service: TeamAlertPrefsSyncService
    /// National-team alerts go to a SEPARATE table (`competition_alert_preferences`), keyed by
    /// `follow_key` ("nt:USA"), because a FIFA code doesn't fit the club-id-keyed table and would
    /// muddy the watcher's club joins. The unified TeamAlertStore holds both kinds; this coordinator
    /// routes each edit/reconcile to the right table by realm.
    private let competition: CompetitionAlertPrefsSyncService

    /// Shadow of the followed CLUB set, to detect which clubs *left* (→ clear alerts).
    private var knownFollows: Set<String>
    /// Shadow of the followed NATIONAL-TEAM codes, same purpose.
    private var knownNTFollows: Set<String>
    /// Last identity we reconciled for, so a sign-in / user switch re-pulls.
    private var lastUserID: UUID?
    /// The identity a reconcile CONVERGED for — meaning it was allowed to prune, not merely that it
    /// started. Anything short of that leaves this nil so the observation re-drives it.
    ///
    /// ⚠️ Two distinct passes fall short, and both must retry:
    ///   • the fully-empty bail (reinstall + restored Keychain session, before the picker lands);
    ///   • a MID-ONBOARDING pass, which may push but must never prune (see `mayPrune`).
    /// Marking either one done would strand the account: nothing else fires afterwards, so the stale
    /// server rows from the previous install would keep the watcher pushing for teams the user did
    /// not re-pick. `observe()` therefore tracks `hasOnboarded` as well, and the flip re-drives the
    /// one reconcile that can actually converge.
    private var reconciledForUserID: UUID?

    init(
        auth: AuthStore,
        alerts: TeamAlertStore,
        following: FollowingStore,
        service: TeamAlertPrefsSyncService = TeamAlertPrefsSyncService(),
        competition: CompetitionAlertPrefsSyncService = CompetitionAlertPrefsSyncService()
    ) {
        self.auth = auth
        self.alerts = alerts
        self.following = following
        self.service = service
        self.competition = competition
        self.knownFollows = following.followedIDs
        self.knownNTFollows = following.followedNationalTeams
    }

    // MARK: - Realm helpers (a key is a national team iff it's a followed FIFA code)

    /// The Supabase `follow_key` for a FIFA code ("USA" → "nt:USA").
    private static func ntKey(_ code: String) -> String { "nt:\(code)" }

    /// Wire up sync. Call once, after `auth.restoreSession()` AND after the store's
    /// one-time migration, from RootTabView.
    func start() {
        lastUserID = auth.userID

        // Mirror each on/off edit up, routed to the right table by realm. No-op while signed out.
        alerts.onAlertChanged = { [weak self] teamID, enabled in
            guard let self, let userID = self.auth.userID else { return }
            let isNationalTeam = self.following.followedNationalTeams.contains(teamID)
            Task {
                do {
                    if isNationalTeam {
                        try await self.competition.push(followKey: Self.ntKey(teamID), enabled: enabled, userID: userID)
                    } else {
                        try await self.service.push(teamID: teamID, enabled: enabled, userID: userID)
                    }
                } catch {
                    Diagnostics.shared.record(.apiFailure, "alert push \(teamID): \(error.localizedDescription)")
                    await self.auth.revalidateIfUnauthorizedWrite(error)
                }
            }
        }

        reconcileIfSignedIn()   // covers an already-restored session
        observe()
    }

    // MARK: - Observation

    /// Re-arm observation of the signed-in user (sign-in → reconcile), the followed set (unfollow →
    /// clear that team's alerts), and `hasOnboarded`.
    ///
    /// ⚠️ `hasOnboarded` is tracked because it is the ONLY signal that a reconcile may now prune, and
    /// nothing else announces it: `completeOnboarding()` mutates that flag alone — no follow changes,
    /// so `followedIDs` doesn't fire — and its `onOnboardingCompleted` hook is already claimed by
    /// FollowSyncCoordinator. Without this the first prune-eligible reconcile would wait for the next
    /// cold launch, leaving the previous install's teams pushing in the meantime.
    private func observe() {
        withObservationTracking {
            _ = auth.userID
            _ = following.followedIDs
            _ = following.followedNationalTeams
            _ = following.hasOnboarded
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleFollowsChange()
                if self.auth.userID != self.lastUserID {
                    self.lastUserID = self.auth.userID
                    self.reconcileIfSignedIn()
                } else if let id = self.auth.userID, self.reconciledForUserID != id {
                    // Something changed for an identity that has not CONVERGED yet — the follows just
                    // arrived on an empty device, or onboarding just completed and pruning is finally
                    // allowed. Retry: idempotent, and self-limiting because only a prune-eligible
                    // reconcile marks the identity done.
                    self.reconcileIfSignedIn()
                }
                self.observe()
            }
        }
    }

    // MARK: - Unfollow → clear alerts

    /// Any team that dropped out of the followed set loses its alerts (alerts
    /// require following). `clearAlerts` fires `onAlertChanged`, which pushes
    /// `alerts_enabled = false` up, completing the rule end-to-end.
    private func handleFollowsChange() {
        let current = following.followedIDs
        for id in knownFollows.subtracting(current) { alerts.clearAlerts(for: id) }
        knownFollows = current

        // Same rule for national teams: unfollowing one clears its alerts. `NationalTeamCard`
        // already clears at the UI level; this is the coordinator-level safety net for any surface.
        let currentNT = following.followedNationalTeams
        for code in knownNTFollows.subtracting(currentNT) { alerts.clearAlerts(for: code) }
        knownNTFollows = currentNT
    }

    // MARK: - Sign-in reconcile

    /// Pure set-logic for the reconcile (extracted so it's unit-testable without the network).
    ///
    /// The device's ON set is the truth, intersected with `followed` so alerts ⊆ follows (an alert on
    /// an un-followed team is a ghost and gets dropped here, then deleted server-side).
    ///
    /// ⚠️ **An empty `localOn` now yields an EMPTY set, and that is the intended answer** — it used to
    /// fall back to a `restoreSource` pulled from the server. "No bells on this device" means the user
    /// has none, not that we lost them. The caller is what makes this safe: it only lets the resulting
    /// prune run once onboarding has completed, so a half-filled picker can never look authoritative
    /// (the same rule `FollowSyncCoordinator.resolveFollowOps` applies to follows).
    nonisolated static func authoritativeOnSet(
        localOn: Set<String>, followed: Set<String>
    ) -> Set<String> {
        localOn.intersection(followed)
    }

    private func reconcileIfSignedIn() {
        guard let userID = auth.userID else { return }
        Task {
            // "Followed" spans BOTH realms now — clubs (ESPN ids) AND national teams (FIFA codes) —
            // so an NT code is no longer intersected away (the bug that deleted "USA" alert rows).
            let clubFollows = following.followedIDs
            let ntFollows = following.followedNationalTeams
            let followed = clubFollows.union(ntFollows)
            let localOn = alerts.teamsWithAlerts()
            // Nothing on the device yet (no alerts AND no follows): a not-yet-populated device.
            // Bail WITHOUT marking, so the observation retries once the picker lands.
            guard !(localOn.isEmpty && followed.isEmpty) else { return }

            // ⚠️ PRUNING IS GATED ON ONBOARDING — the single most important line here.
            // Deleting rows is how the device's choice reaches the server, but a picker that is only
            // half-filled must never look authoritative: mid-onboarding the user may have picked one
            // club of three, so wiping the server now would destroy choices they are still making.
            // Pushes are always safe (they only ever ADD intent); deletes wait. Same rule, same
            // reason, as `FollowSyncCoordinator.resolveFollowOps`.
            let mayPrune = following.hasOnboarded
            // Only a pass that could actually converge counts as done (see `reconciledForUserID`).
            if mayPrune { reconciledForUserID = userID }
            do {
                // Device-authoritative, always: converge the server to what is on this phone.
                // An empty local set is a legitimate answer ("no bells"), not a signal to restore.
                let authoritative = Self.authoritativeOnSet(localOn: localOn, followed: followed)
                alerts.replaceEnabled(authoritative)

                // Partition by realm and converge EACH table independently. A legacy "USA" row
                // mis-written into team_alert_preferences falls out of `clubAuth` (USA ∉ clubFollows)
                // and is pruned by the club loop below → auto-cleanup.
                let clubAuth = authoritative.intersection(clubFollows)
                let ntAuth = authoritative.intersection(ntFollows)

                // Club table.
                let allRemoteClub = try await service.fetchAllTeamIDs(userID: userID)
                for teamID in clubAuth {
                    do { try await service.push(teamID: teamID, enabled: true, userID: userID) }
                    catch { Diagnostics.shared.record(.apiFailure, "team-alert reconcile push \(teamID): \(error.localizedDescription)") }
                }
                if mayPrune {
                    // ⚠️ Re-read the ON set AFTER the awaits. A bell tapped while those fetches were in
                    // flight is absent from the snapshot taken at the top, so pruning against that
                    // stale set would DELETE the row the tap just created — leaving the bell ON
                    // locally with no server row, and nothing to re-push it. The bell-intercept
                    // sign-in makes exactly that interleaving reachable (the deferred activation runs
                    // alongside this reconcile). Never prune a team that is currently ON.
                    let liveOn = alerts.teamsWithAlerts()
                    for teamID in allRemoteClub.subtracting(clubAuth).subtracting(liveOn) {
                        do { try await service.delete(teamID: teamID, userID: userID) }
                        catch { Diagnostics.shared.record(.apiFailure, "team-alert reconcile prune \(teamID): \(error.localizedDescription)") }
                    }
                }

                // National-team table (keyed by "nt:CODE").
                let ntAuthKeys = Set(ntAuth.map(Self.ntKey))
                let allRemoteNT = try await competition.fetchAllKeys(userID: userID)
                for key in ntAuthKeys {
                    do { try await competition.push(followKey: key, enabled: true, userID: userID) }
                    catch { Diagnostics.shared.record(.apiFailure, "nt-alert reconcile push \(key): \(error.localizedDescription)") }
                }
                if mayPrune {
                    // Same re-read, same reason, in the national-team realm.
                    let liveOnKeys = Set(alerts.teamsWithAlerts().map(Self.ntKey))
                    for key in allRemoteNT.subtracting(ntAuthKeys).subtracting(liveOnKeys) {
                        do { try await competition.delete(followKey: key, userID: userID) }
                        catch { Diagnostics.shared.record(.apiFailure, "nt-alert reconcile prune \(key): \(error.localizedDescription)") }
                    }
                }
            } catch {
                Diagnostics.shared.record(.apiFailure, "team-alert reconcile: \(error.localizedDescription)")
            }
        }
    }
}
