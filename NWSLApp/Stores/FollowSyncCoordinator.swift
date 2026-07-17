//
//  FollowSyncCoordinator.swift
//  NWSLApp
//
//  Owns the bridge between local follows (FollowingStore / UserDefaults) and the
//  server (Supabase `follows` table). This is the ONLY place the sync service
//  touches the follow path — FollowingStore stays pure and dependency-free, and
//  AuthStore stays ignorant of follows. The coordinator depends on both; neither
//  depends on it (it isn't even in the environment — RootTabView just holds it
//  alive and calls `start()`).
//
//  Two jobs:
//   1. Reconcile on sign-in — when `auth.currentUser` goes nil → a user, merge
//      local + server follows (UNION, never delete), write the union back down to
//      local (covers new-device restore), and push the union up to Supabase
//      (covers first-sign-in upload). See the session doc §4.
//   2. Sync-up ongoing — once signed in, each local toggle mirrors the single
//      changed team to Supabase via the FollowingStore.onFollowsChanged hook.
//
//  Offline-first: every network step is best-effort. Local writes always succeed
//  first, so a failed server call just means we reconcile again next launch.
//
//  `@MainActor` because it reads/writes SwiftUI-observed state (FollowingStore,
//  AuthStore) and uses withObservationTracking, which must register on the actor
//  that mutates the observed values.
//

import Foundation
import Observation

@MainActor
@Observable
final class FollowSyncCoordinator {
    private let following: FollowingStore
    private let auth: AuthStore
    private let service: FollowSyncService
    private let compService: CompetitionFollowSyncService

    /// The follow set we believe the server holds, so an ongoing toggle can push
    /// just the delta (one added/removed id) rather than the whole set. Seeded by
    /// `reconcile` and kept current by `handleLocalChange`.
    private var knownFollows: Set<String> = []

    /// The competition-follow key set ("nt:USA", "concacaf") we believe the server
    /// holds — the twin of `knownFollows` for the `competition_follows` table.
    private var knownCompetitionFollows: Set<String> = []

    /// Last user id we reconciled, so we only run the (heavier) merge on an actual
    /// nil → user (or user → different-user) transition, not on every observation.
    private var lastUserID: UUID?

    /// True once the FOLLOWS reconcile has finished for this launch (success OR failure).
    /// The root gate reads this so a signed-in user sees a brief "Restoring…" state until the
    /// server set is known, instead of flashing the onboarding picker (which used to race the
    /// restore). Stays true thereafter; only the first launch restore gates onboarding.
    private(set) var restoreResolved = false

    init(following: FollowingStore, auth: AuthStore,
         service: FollowSyncService = FollowSyncService(),
         compService: CompetitionFollowSyncService = CompetitionFollowSyncService()) {
        self.following = following
        self.auth = auth
        self.service = service
        self.compService = compService
    }

    /// Wire up sync. Call once, after `auth.restoreSession()`, from RootTabView.
    func start() {
        // Arm ongoing sync-up. Harmless while signed out (handleLocalChange just
        // tracks the set and returns without a network call).
        following.onFollowsChanged = { [weak self] ids in
            self?.handleLocalChange(ids)
        }
        following.onCompetitionFollowKeysChanged = { [weak self] keys in
            self?.handleCompetitionLocalChange(keys)
        }

        // If a session was already restored on launch, reconcile now (the
        // relaunch / new-device restore path).
        if let userID = auth.userID {
            lastUserID = userID
            reconcile(userID: userID)
        }

        observeAuth()
    }

    // MARK: - Auth observation

    /// Re-arming observation of `auth.currentUser`. `withObservationTracking`'s
    /// onChange fires once, just *before* the value changes, so we hop onto the
    /// main actor (where the new value is readable) to handle it, then re-register.
    private func observeAuth() {
        withObservationTracking {
            _ = auth.userID
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleAuthChange()
                self.observeAuth()
            }
        }
    }

    private func handleAuthChange() {
        let newID = auth.userID
        defer { lastUserID = newID }
        if let newID, newID != lastUserID {
            // Signed in (or switched user) → reconcile local ⟷ server.
            reconcile(userID: newID)
        }
        // Signed out (newID == nil): nothing to do — local follows stay put, and
        // handleLocalChange's signed-out guard stops further pushes.
    }

    // MARK: - Reconcile (sign-in / restore)

    private func reconcile(userID: UUID) {
        Task {
            defer { restoreResolved = true }   // gate flips once the server set is known (success or fail)
            let local = following.followedIDs
            do {
                let remote = try await service.fetchRemoteFollows(userID: userID)
                // Launch reconcile is RESTORE-ONLY — it never deletes a server row. Unfollows
                // propagate solely through `handleLocalChange` (an explicit signed-in unfollow),
                // so no launch-time race can prune. The device is only authoritative once it has
                // genuinely onboarded AND has a non-empty set; a wiped/reinstalled device
                // (`hasOnboarded == false`) restores the FULL server set regardless of any
                // onboarding-tap timing (the old `local.isEmpty ? …` latched onto a partial set
                // mid-onboarding and pruned the rest — the reinstall data-loss bug).
                let authoritative = (following.hasOnboarded && !local.isEmpty) ? local : remote
                // TEMP (reinstall-restore verification — remove after verified): prove the branch
                // restores the full server set and that no prune runs. Readable via the proxy's
                // GET /telemetry/recent.
                Diagnostics.shared.record(.debugTrace,
                    "reconcile local=\(local.count)\(local.sorted()) remote=\(remote.count)\(remote.sorted()) onboarded=\(following.hasOnboarded) → authoritative=\(authoritative == local ? "local" : "remote")(\(authoritative.count))")
                following.replace(ids: authoritative)   // sync-down / restore (no-op when device wins)
                knownFollows = authoritative
                for id in authoritative.subtracting(remote) {   // upload local-only adds (never deletes)
                    do { try await service.addFollow(id, userID: userID) }
                    catch { Diagnostics.shared.record(.apiFailure, "follows reconcile add \(id): \(error.localizedDescription)") }
                }
                // NO prune here: removing a server row only ever happens via an explicit user
                // unfollow (handleLocalChange.removeFollow), never on launch reconcile.
                if !authoritative.isEmpty { following.completeOnboarding() }   // returning signed-in user → hub, not picker
            } catch {
                // Offline / transient: local state is already correct; we'll reconcile again
                // on the next launch. NOT silent — flag it so a persistent sync failure (e.g.
                // a missing RLS GRANT) surfaces instead of follows quietly never syncing.
                Diagnostics.shared.record(.apiFailure, "follows reconcile: \(error.localizedDescription)")
                knownFollows = following.followedIDs
            }
        }
        reconcileCompetitions(userID: userID)
    }

    /// The competition twin of `reconcile` — same device-authoritative mirror against
    /// the `competition_follows` table (national teams + the Champions Cup toggle).
    private func reconcileCompetitions(userID: UUID) {
        Task {
            let local = following.competitionFollowKeys
            do {
                let remote = try await compService.fetchRemoteFollows(userID: userID)
                // Restore-only, same contract as `reconcile`: an un-onboarded/wiped device restores
                // the full server set; never prune on launch (competition unfollows propagate via
                // handleCompetitionLocalChange only).
                let authoritative = (following.hasOnboarded && !local.isEmpty) ? local : remote
                following.replaceCompetitionFollowKeys(authoritative)   // sync-down / restore
                knownCompetitionFollows = authoritative
                for key in authoritative.subtracting(remote) {   // upload local-only adds (never deletes)
                    do { try await compService.addFollow(key, userID: userID) }
                    catch { Diagnostics.shared.record(.apiFailure, "competition reconcile add \(key): \(error.localizedDescription)") }
                }
                // NO prune here (see reconcile): explicit unfollow only.
            } catch {
                Diagnostics.shared.record(.apiFailure, "competition reconcile: \(error.localizedDescription)")
                knownCompetitionFollows = following.competitionFollowKeys
            }
        }
    }

    // MARK: - Ongoing sync-up

    private func handleLocalChange(_ ids: Set<String>) {
        guard let userID = auth.userID else {
            // Signed out: keep our shadow current so the first post-sign-in diff
            // is clean, but don't touch the network.
            knownFollows = ids
            return
        }
        let added = ids.subtracting(knownFollows)
        let removed = knownFollows.subtracting(ids)
        knownFollows = ids
        guard !added.isEmpty || !removed.isEmpty else { return }
        Task {
            for id in added {
                do { try await service.addFollow(id, userID: userID) }
                catch {
                    Diagnostics.shared.record(.apiFailure, "follows addFollow \(id): \(error.localizedDescription)")
                    await auth.revalidateIfUnauthorizedWrite(error)
                }
            }
            for id in removed {
                do { try await service.removeFollow(id, userID: userID) }
                catch {
                    Diagnostics.shared.record(.apiFailure, "follows removeFollow \(id): \(error.localizedDescription)")
                    await auth.revalidateIfUnauthorizedWrite(error)
                }
            }
        }
    }

    /// The competition twin of `handleLocalChange` — mirrors a single toggled
    /// national team / Champions Cup change to `competition_follows`.
    private func handleCompetitionLocalChange(_ keys: Set<String>) {
        guard let userID = auth.userID else {
            knownCompetitionFollows = keys
            return
        }
        let added = keys.subtracting(knownCompetitionFollows)
        let removed = knownCompetitionFollows.subtracting(keys)
        knownCompetitionFollows = keys
        guard !added.isEmpty || !removed.isEmpty else { return }
        Task {
            for key in added {
                do { try await compService.addFollow(key, userID: userID) }
                catch {
                    Diagnostics.shared.record(.apiFailure, "competition addFollow \(key): \(error.localizedDescription)")
                    await auth.revalidateIfUnauthorizedWrite(error)
                }
            }
            for key in removed {
                do { try await compService.removeFollow(key, userID: userID) }
                catch {
                    Diagnostics.shared.record(.apiFailure, "competition removeFollow \(key): \(error.localizedDescription)")
                    await auth.revalidateIfUnauthorizedWrite(error)
                }
            }
        }
    }
}
