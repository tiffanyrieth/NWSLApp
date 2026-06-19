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
//  On sign-in it reconciles: pull the server's rows, fill any gaps locally (LOCAL
//  wins — the device owns intent, incl. the migration seed), then push the merged
//  set back up. All network steps are best-effort; the local toggles work regardless.
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

    /// Shadow of the followed set, to detect which teams *left* (→ clear alerts).
    private var knownFollows: Set<String>
    /// Last identity we reconciled for, so a sign-in / user switch re-pulls.
    private var lastUserID: UUID?

    init(
        auth: AuthStore,
        alerts: TeamAlertStore,
        following: FollowingStore,
        service: TeamAlertPrefsSyncService = TeamAlertPrefsSyncService()
    ) {
        self.auth = auth
        self.alerts = alerts
        self.following = following
        self.service = service
        self.knownFollows = following.followedIDs
    }

    /// Wire up sync. Call once, after `auth.restoreSession()` AND after the store's
    /// one-time migration, from RootTabView.
    func start() {
        lastUserID = auth.userID

        // Mirror each on/off edit up. No-op while signed out.
        alerts.onAlertChanged = { [weak self] teamID, enabled in
            guard let self, let userID = self.auth.userID else { return }
            Task {
                do { try await self.service.push(teamID: teamID, enabled: enabled, userID: userID) }
                catch { Diagnostics.shared.record(.apiFailure, "team-alert push \(teamID): \(error.localizedDescription)") }
            }
        }

        reconcileIfSignedIn()   // covers an already-restored session
        observe()
    }

    // MARK: - Observation

    /// Re-arm observation of the signed-in user (sign-in → reconcile) and the
    /// followed set (unfollow → clear that team's alerts).
    private func observe() {
        withObservationTracking {
            _ = auth.userID
            _ = following.followedIDs
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleFollowsChange()
                if self.auth.userID != self.lastUserID {
                    self.lastUserID = self.auth.userID
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
        let removed = knownFollows.subtracting(current)
        for id in removed { alerts.clearAlerts(for: id) }
        knownFollows = current
    }

    // MARK: - Sign-in reconcile

    /// Pull the server's enabled set, union it locally, then push every locally
    /// enabled team up so the seeded/edited state lands server-side. Best-effort.
    private func reconcileIfSignedIn() {
        guard let userID = auth.userID else { return }
        Task {
            do {
                let remote = try await service.fetchAll(userID: userID)
                alerts.mergeFromRemote(remote)
            } catch {
                Diagnostics.shared.record(.apiFailure, "team-alert fetchAll: \(error.localizedDescription)")
            }
            // Push every locally enabled team up (idempotent upserts on the composite key).
            for teamID in alerts.teamsWithAlerts() {
                do { try await service.push(teamID: teamID, enabled: true, userID: userID) }
                catch { Diagnostics.shared.record(.apiFailure, "team-alert reconcile push \(teamID): \(error.localizedDescription)") }
            }
        }
    }
}
