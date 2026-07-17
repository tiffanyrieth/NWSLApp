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
    /// A `follow_key` back to its FIFA code ("nt:USA" → "USA").
    private static func code(fromKey key: String) -> String {
        key.hasPrefix("nt:") ? String(key.dropFirst(3)) : key
    }

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

    /// Re-arm observation of the signed-in user (sign-in → reconcile) and the
    /// followed set (unfollow → clear that team's alerts).
    private func observe() {
        withObservationTracking {
            _ = auth.userID
            _ = following.followedIDs
            _ = following.followedNationalTeams
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
        for id in knownFollows.subtracting(current) { alerts.clearAlerts(for: id) }
        knownFollows = current

        // Same rule for national teams: unfollowing one clears its alerts. `NationalTeamCard`
        // already clears at the UI level; this is the coordinator-level safety net for any surface.
        let currentNT = following.followedNationalTeams
        for code in knownNTFollows.subtracting(currentNT) { alerts.clearAlerts(for: code) }
        knownNTFollows = currentNT
    }

    // MARK: - Sign-in reconcile

    /// Device-authoritative mirror reconcile. The on-device ON set is the truth; the
    /// server is reconciled to match it EXACTLY — kept teams pushed `true`, every other
    /// row deleted (stale `true` ghosts from an uninstall + leftover `false` clutter).
    /// Two safety rules:
    ///   • Empty-local guardrail: if the device has no local ON set, restore from the
    ///     server instead of wiping it (new-device / reinstall-without-onboarding).
    ///   • Alerts require following: the authoritative set is intersected with the
    ///     followed set, so an alert for an un-followed team (a ghost) is dropped here
    ///     and deleted server-side. Onboarding populates follows before any sign-in is
    ///     possible, so `followed` is reliably set on every real reconcile.
    /// A fully-empty local state (no alerts AND no follows — a not-yet-populated restore)
    /// bails without touching the server, so sign-in can never wipe an account.
    /// Pure set-logic for the reconcile (extracted so it's unit-testable without the
    /// network). `restoreSource` is the server's enabled set, used ONLY when the device
    /// has no local ON set (empty-local guardrail → restore). Otherwise the device wins.
    /// Always intersected with `followed` so alerts ⊆ follows (drops ghost alerts).
    nonisolated static func authoritativeOnSet(
        localOn: Set<String>, followed: Set<String>, restoreSource: Set<String>
    ) -> Set<String> {
        let base = localOn.isEmpty ? restoreSource : localOn
        return base.intersection(followed)
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
            guard !(localOn.isEmpty && followed.isEmpty) else { return }
            do {
                // Empty-local restore pulls BOTH tables (club ids + NT codes from "nt:CODE" keys).
                var restoreSource: Set<String> = []
                if localOn.isEmpty {
                    async let clubRestore = service.fetchAll(userID: userID)
                    async let ntRestore = competition.fetchAll(userID: userID)
                    restoreSource = try await clubRestore.union((try await ntRestore).map(Self.code(fromKey:)))
                }
                let authoritative = Self.authoritativeOnSet(
                    localOn: localOn, followed: followed, restoreSource: restoreSource)
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
                for teamID in allRemoteClub.subtracting(clubAuth) {
                    do { try await service.delete(teamID: teamID, userID: userID) }
                    catch { Diagnostics.shared.record(.apiFailure, "team-alert reconcile prune \(teamID): \(error.localizedDescription)") }
                }

                // National-team table (keyed by "nt:CODE").
                let ntAuthKeys = Set(ntAuth.map(Self.ntKey))
                let allRemoteNT = try await competition.fetchAllKeys(userID: userID)
                for key in ntAuthKeys {
                    do { try await competition.push(followKey: key, enabled: true, userID: userID) }
                    catch { Diagnostics.shared.record(.apiFailure, "nt-alert reconcile push \(key): \(error.localizedDescription)") }
                }
                for key in allRemoteNT.subtracting(ntAuthKeys) {
                    do { try await competition.delete(followKey: key, userID: userID) }
                    catch { Diagnostics.shared.record(.apiFailure, "nt-alert reconcile prune \(key): \(error.localizedDescription)") }
                }
            } catch {
                Diagnostics.shared.record(.apiFailure, "team-alert reconcile: \(error.localizedDescription)")
            }
        }
    }
}
