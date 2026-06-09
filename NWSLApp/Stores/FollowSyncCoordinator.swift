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

    /// The follow set we believe the server holds, so an ongoing toggle can push
    /// just the delta (one added/removed id) rather than the whole set. Seeded by
    /// `reconcile` and kept current by `handleLocalChange`.
    private var knownFollows: Set<String> = []

    /// Last user id we reconciled, so we only run the (heavier) merge on an actual
    /// nil → user (or user → different-user) transition, not on every observation.
    private var lastUserID: UUID?

    init(following: FollowingStore, auth: AuthStore, service: FollowSyncService = FollowSyncService()) {
        self.following = following
        self.auth = auth
        self.service = service
    }

    /// Wire up sync. Call once, after `auth.restoreSession()`, from RootTabView.
    func start() {
        // Arm ongoing sync-up. Harmless while signed out (handleLocalChange just
        // tracks the set and returns without a network call).
        following.onFollowsChanged = { [weak self] ids in
            self?.handleLocalChange(ids)
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
            let local = following.followedIDs
            do {
                let remote = try await service.fetchRemoteFollows(userID: userID)
                let union = local.union(remote)
                following.merge(ids: union)   // sync-down (also restores on a new device)
                knownFollows = union
                try await service.pushFollows(union, userID: userID)  // sync-up
            } catch {
                // Offline / transient: local state is already correct; we'll
                // reconcile again on the next launch.
                print("[FollowSyncCoordinator] reconcile failed: \(error)")
                knownFollows = following.followedIDs
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
                try? await service.addFollow(id, userID: userID)
            }
            for id in removed {
                try? await service.removeFollow(id, userID: userID)
            }
        }
    }
}
