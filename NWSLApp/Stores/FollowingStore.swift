//
//  FollowingStore.swift
//  NWSLApp
//
//  The personalization "lens": which clubs the user follows. This is shared
//  app-wide and injected via SwiftUI's `.environment()` rather than owned by a
//  single screen — because many surfaces read the same following set (Teams
//  now; Home / Feed / notifications later). That's why it lives in its own
//  `Stores/` folder, distinct from the per-screen ViewModels: a ViewModel owns
//  one screen's state, a Store owns shared app state.
//
//  Persistence: a small set of club IDs is a textbook fit for `UserDefaults`.
//  SwiftData would be overkill here, and this is trivially swappable later if
//  the followed model grows (e.g. players too) — matches CLAUDE.md's
//  "start in-memory / simplest thing that works, add SwiftData if needed."
//

import Foundation

@Observable
final class FollowingStore {
    /// Followed club IDs (ESPN team IDs). Read-only to the outside; mutate
    /// through `toggle(_:)` so persistence always stays in sync.
    private(set) var followedIDs: Set<String>

    /// Followed international competition IDs (Competition.id slugs). A separate
    /// set from clubs because they're a different kind of thing with a different
    /// source (a curated list, not ESPN's /teams). Persisted the same way.
    private(set) var followedCompetitionIDs: Set<String>

    /// Whether the user has been through the first-open onboarding ("Make it
    /// yours" team picker). Drives whether Home shows onboarding or the hub.
    /// Persisted so it survives launches — onboarding is a one-time gate.
    private(set) var hasOnboarded: Bool

    /// Whether the one-time post-onboarding "save your picks" sign-in prompt has
    /// been shown. Persisted so it appears exactly once, ever — skipping is fine,
    /// the app never nags (see Reference/Sessions/2026-06-09_supabase-accounts-setup §2).
    private(set) var hasSeenSignInPrompt: Bool

    /// Called after any local follow mutation, with the new full set. Optional and
    /// nil by default — when nil (signed-out, tests, previews) the store behaves
    /// exactly as before. FollowSyncCoordinator sets it after sign-in to mirror
    /// changes up to Supabase. The store stays dependency-free: it knows nothing
    /// about the network, only that "something" may want to observe changes.
    var onFollowsChanged: ((Set<String>) -> Void)?

    private let defaults: UserDefaults
    // Static so the DEBUG reset helper (which has no instance) shares the exact
    // same key names — one source of truth, no drift.
    private static let storageKey = "followedClubIDs"
    private static let competitionsKey = "followedCompetitionIDs"
    private static let onboardedKey = "hasOnboarded"
    private static let signInPromptKey = "hasSeenSignInPrompt"

    /// `defaults` is injectable so tests (and previews) can use an isolated
    /// store instead of the app's real preferences.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.stringArray(forKey: Self.storageKey) ?? []
        self.followedIDs = Set(saved)
        self.followedCompetitionIDs = Set(defaults.stringArray(forKey: Self.competitionsKey) ?? [])
        // Treat anyone who already follows a club as onboarded, so existing
        // users (and seeded simulators) don't get sent back through the picker.
        self.hasOnboarded = defaults.bool(forKey: Self.onboardedKey) || !saved.isEmpty
        self.hasSeenSignInPrompt = defaults.bool(forKey: Self.signInPromptKey)
    }

    func isFollowing(_ club: Club) -> Bool {
        followedIDs.contains(club.id)
    }

    /// Follow if not followed, unfollow if already followed; persists either way.
    func toggle(_ club: Club) {
        if followedIDs.contains(club.id) {
            followedIDs.remove(club.id)
        } else {
            followedIDs.insert(club.id)
        }
        defaults.set(Array(followedIDs), forKey: Self.storageKey)
        // Notify the sync coordinator (if armed) so the change mirrors up to
        // Supabase. No-op when signed out — the closure is nil.
        onFollowsChanged?(followedIDs)
    }

    /// Union `ids` into the followed set and persist once. Union-only — never
    /// removes a follow, matching the sign-in merge policy. Used by
    /// FollowSyncCoordinator for both the sign-in merge and new-device restore.
    /// Deliberately does NOT fire `onFollowsChanged`: the coordinator is the
    /// caller and already knows, so this avoids a sync-down echoing back as a
    /// sync-up.
    func merge(ids: Set<String>) {
        let merged = followedIDs.union(ids)
        guard merged != followedIDs else { return }
        followedIDs = merged
        defaults.set(Array(followedIDs), forKey: Self.storageKey)
    }

    func isFollowing(_ competition: FollowedCompetition) -> Bool {
        followedCompetitionIDs.contains(competition.id)
    }

    /// Follow/unfollow a competition; persists either way. Mirrors `toggle(_:)`
    /// for clubs so the onboarding rows behave identically.
    func toggle(_ competition: FollowedCompetition) {
        if followedCompetitionIDs.contains(competition.id) {
            followedCompetitionIDs.remove(competition.id)
        } else {
            followedCompetitionIDs.insert(competition.id)
        }
        defaults.set(Array(followedCompetitionIDs), forKey: Self.competitionsKey)
    }

    /// Mark onboarding finished (the "Follow N teams" button). One-way: once
    /// onboarded, Home always opens onto the hub, not the picker.
    func completeOnboarding() {
        hasOnboarded = true
        defaults.set(true, forKey: Self.onboardedKey)
    }

    /// Mark the one-time post-onboarding sign-in prompt as shown. One-way: once
    /// seen, the prompt never appears again (skipping is fine — the app works
    /// identically without an account).
    func markSignInPromptSeen() {
        hasSeenSignInPrompt = true
        defaults.set(true, forKey: Self.signInPromptKey)
    }

    #if DEBUG
    /// Dev-only: reset following + onboarding state so the next launch shows the
    /// first-open "Make it yours" picker. Triggered by the `-resetOnboarding`
    /// launch argument (see `NWSLAppApp.init()`); the point is to re-test
    /// onboarding after the verification scaffold has seeded a follow into the
    /// simulator. Static + key-name-aware so it can run before any store instance
    /// exists, and not compiled into release builds.
    ///
    /// We *write cleared sentinels* (empty arrays / `false`) rather than
    /// `removeObject(forKey:)`. When the seeded values were written by another
    /// process (the scaffold / `xcrun simctl … defaults write`), the app holds a
    /// CFPreferences cache snapshot of them, and key *deletions* don't reliably
    /// propagate against that snapshot in the Simulator — the read-back still
    /// returns the stale value, so the picker never returns. Explicit writes
    /// take, because they're the same path the app's own `toggle()` /
    /// `completeOnboarding()` use. An empty `followedClubIDs` + `hasOnboarded ==
    /// false` reproduces a fresh install for the `init` gate
    /// (`bool(onboardedKey) || !saved.isEmpty`).
    static func debugResetState(defaults: UserDefaults = .standard) {
        defaults.set([String](), forKey: storageKey)
        defaults.set([String](), forKey: competitionsKey)
        defaults.set(false, forKey: onboardedKey)
        // Clear the sign-in-prompt flag too, so a reset re-runs the full
        // post-onboarding flow (prompt included) on the next launch.
        defaults.set(false, forKey: signInPromptKey)
    }
    #endif
}
