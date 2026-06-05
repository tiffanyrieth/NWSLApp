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

    /// Whether the user has been through the first-open onboarding ("Make it
    /// yours" team picker). Drives whether Home shows onboarding or the hub.
    /// Persisted so it survives launches — onboarding is a one-time gate.
    private(set) var hasOnboarded: Bool

    private let defaults: UserDefaults
    private let storageKey = "followedClubIDs"
    private let onboardedKey = "hasOnboarded"

    /// `defaults` is injectable so tests (and previews) can use an isolated
    /// store instead of the app's real preferences.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.stringArray(forKey: storageKey) ?? []
        self.followedIDs = Set(saved)
        // Treat anyone who already follows a club as onboarded, so existing
        // users (and seeded simulators) don't get sent back through the picker.
        self.hasOnboarded = defaults.bool(forKey: onboardedKey) || !saved.isEmpty
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
        defaults.set(Array(followedIDs), forKey: storageKey)
    }

    /// Mark onboarding finished (the "Follow N teams" button). One-way: once
    /// onboarded, Home always opens onto the hub, not the picker.
    func completeOnboarding() {
        hasOnboarded = true
        defaults.set(true, forKey: onboardedKey)
    }
}
