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
//  ⚠️ UPWARD-ONLY (owner decision, 2026-07-23). Sync is one-directional: the DEVICE
//  is the source of truth for follows and Supabase is backend bookkeeping the user
//  never hears about. There is NO restore-down: signing in never rewrites local
//  follows, never completes onboarding, and never changes what's on screen.
//
//  Why the old restore-down was removed: it existed to let a returning user skip
//  onboarding, which buys nothing (16 clubs, ~2 seconds to re-pick) while the thing
//  a user would actually mourn — Fan Zone progress — is restored separately by
//  ProgressSyncService. Worse, it assumed "a signed-in user IS a returning user
//  (onboarding precedes sign-in)", which the Tier-2 alert-bell intercept made false:
//  signing in MID-onboarding hijacked the picker, skipped to Home, and overwrote the
//  clubs already tapped.
//
//  Two jobs:
//   1. Reconcile on sign-in — push local → server (see `resolveFollowOps`). Adds
//      always; deletes only once onboarding is finished, so a half-filled picker can
//      never prune the server (the original "only the oldest follow survives" bug).
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
        // Finishing the picker is the first moment the device may prune the server (see
        // `resolveFollowOps`) — matters for the sign-in-mid-onboarding path.
        following.onOnboardingCompleted = { [weak self] in
            self?.onOnboardingCompleted()
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

    // MARK: - Reconcile (sign-in — UPWARD ONLY)

    /// Decide which server rows to add/remove so the server matches the device. PURE (no store, no
    /// network) so every branch is unit-tested — the untested inline version of this logic is exactly
    /// what regressed. Mirrors `TeamAlertSyncCoordinator.authoritativeOnSet`, the twin that didn't.
    ///
    /// The `hasOnboarded` split is the whole safety property:
    ///  • **false** — the picker is on screen (or a fresh/wiped install). `local` is a PARTIAL set that
    ///    the user is still building, so ADD what's there but NEVER delete: pruning against a half-filled
    ///    picker is the "only the oldest follow survives" data-loss bug.
    ///  • **true** — onboarding is finished, so the device is authoritative and the server is made to
    ///    match exactly, deletes included. Safe now only because the mid-onboarding case above can no
    ///    longer reach this branch.
    nonisolated static func resolveFollowOps(local: Set<String>, remote: Set<String>,
                                             hasOnboarded: Bool) -> (add: Set<String>, remove: Set<String>) {
        (add: local.subtracting(remote),
         remove: hasOnboarded ? remote.subtracting(local) : [])
    }

    /// Push local follows up to the server. Never touches local state: signing in must not change a
    /// single thing the user can see (no picker takeover, no onboarding skip, no re-checked clubs).
    private func reconcile(userID: UUID) {
        Task {
            let local = following.followedIDs
            do {
                let remote = try await service.fetchRemoteFollows(userID: userID)
                let ops = Self.resolveFollowOps(local: local, remote: remote,
                                                hasOnboarded: following.hasOnboarded)
                knownFollows = local
                for id in ops.add {
                    do { try await service.addFollow(id, userID: userID) }
                    catch { Diagnostics.shared.record(.apiFailure, "follows reconcile add \(id): \(error.localizedDescription)") }
                }
                for id in ops.remove {
                    do { try await service.removeFollow(id, userID: userID) }
                    catch { Diagnostics.shared.record(.apiFailure, "follows reconcile remove \(id): \(error.localizedDescription)") }
                }
            } catch {
                // Offline / transient: local state is already correct (it's the source of truth), so
                // there is nothing to repair — we just couldn't mirror it up. Reconciles again next
                // launch. NOT silent: a persistent failure (e.g. a missing RLS GRANT) must surface.
                Diagnostics.shared.record(.apiFailure, "follows reconcile: \(error.localizedDescription)")
                knownFollows = local
            }
        }
        reconcileCompetitions(userID: userID)
    }

    /// Called when the user finishes onboarding while already signed in (the alert-bell intercept path:
    /// sign in mid-picker, keep picking, then tap "Follow N teams"). Until that moment `resolveFollowOps`
    /// deliberately withholds deletes, so this is the first point where the device may prune the server.
    func onOnboardingCompleted() {
        guard let userID = auth.userID else { return }
        reconcile(userID: userID)
    }

    /// The competition twin of `reconcile` — same UPWARD-ONLY contract against the
    /// `competition_follows` table (national teams + the Champions Cup toggle).
    private func reconcileCompetitions(userID: UUID) {
        Task {
            let local = following.competitionFollowKeys
            do {
                let remote = try await compService.fetchRemoteFollows(userID: userID)
                // Same rule + same reasoning as `resolveFollowOps` (shared helper): add always, delete
                // only once onboarding is done. Never writes back down — local is the source of truth.
                let ops = Self.resolveFollowOps(local: local, remote: remote,
                                                hasOnboarded: following.hasOnboarded)
                knownCompetitionFollows = local
                for key in ops.add {
                    do { try await compService.addFollow(key, userID: userID) }
                    catch { Diagnostics.shared.record(.apiFailure, "competition reconcile add \(key): \(error.localizedDescription)") }
                }
                for key in ops.remove {
                    do { try await compService.removeFollow(key, userID: userID) }
                    catch { Diagnostics.shared.record(.apiFailure, "competition reconcile remove \(key): \(error.localizedDescription)") }
                }
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
