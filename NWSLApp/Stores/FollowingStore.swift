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

    /// The CONCACAF W Champions Cup global toggle (a CLUB competition). On ⇒ followed
    /// clubs in the current draw pipe their Champions Cup matches into the Schedule's
    /// "My teams". One switch covers all qualifying clubs (no per-club granularity).
    private(set) var isConcacafFollowed: Bool

    /// Followed women's national-team FIFA codes ("USA", "MEX"…) — a new kind of
    /// followable entity that sits alongside clubs in "My teams"; their matches are
    /// filtered out of the national-team ESPN feeds by code.
    private(set) var followedNationalTeams: Set<String>

    /// Whether the user has been through the first-open onboarding ("Make it
    /// yours" team picker). Drives whether Home shows onboarding or the hub.
    /// Persisted so it survives launches — onboarding is a one-time gate.
    private(set) var hasOnboarded: Bool

    /// Called after any local follow mutation, with the new full set. Optional and
    /// nil by default — when nil (signed-out, tests, previews) the store behaves
    /// exactly as before. FollowSyncCoordinator sets it after sign-in to mirror
    /// changes up to Supabase. The store stays dependency-free: it knows nothing
    /// about the network, only that "something" may want to observe changes.
    var onFollowsChanged: ((Set<String>) -> Void)?

    /// Fired after a Champions Cup toggle or national-team follow change, so the
    /// Schedule refetches the competition feeds. Distinct from `onFollowsChanged`
    /// (clubs → Supabase sync): this is purely a "the schedule needs new data" signal.
    var onCompetitionFollowsChanged: (() -> Void)?

    /// Called after a competition-follow mutation with the new full key set
    /// (`competitionFollowKeys`), so FollowSyncCoordinator can mirror it to the
    /// `competition_follows` table — the competition twin of `onFollowsChanged`.
    /// nil by default (signed-out / tests / previews behave exactly as before).
    var onCompetitionFollowKeysChanged: ((Set<String>) -> Void)?

    /// Fired once when onboarding completes. FollowSyncCoordinator uses it to run the first
    /// reconcile that is allowed to PRUNE the server: while the picker is up, sync deliberately
    /// adds without deleting (a half-filled picker must never look authoritative), so finishing
    /// onboarding is the moment the device becomes the full source of truth. Same optional-hook
    /// pattern as `onFollowsChanged` — the store stays dependency-free and knows nothing of sync.
    var onOnboardingCompleted: (() -> Void)?

    private let defaults: UserDefaults
    // Static so the DEBUG reset helper (which has no instance) shares the exact
    // same key names — one source of truth, no drift.
    private static let storageKey = "followedClubIDs"
    // Legacy: the pre-Competitions onboarding's curated competition slugs (USWNT,
    // WC, …). Now superseded — migrated into the new model on launch, then cleared.
    private static let legacyCompetitionsKey = "followedCompetitionIDs"
    private static let onboardedKey = "hasOnboarded"
    private static let concacafKey = "isConcacafFollowed"
    private static let nationalTeamsKey = "followedNationalTeamCodes"

    /// `defaults` is injectable so tests (and previews) can use an isolated
    /// store instead of the app's real preferences.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.stringArray(forKey: Self.storageKey) ?? []
        self.followedIDs = Set(saved)
        self.isConcacafFollowed = defaults.bool(forKey: Self.concacafKey)
        self.followedNationalTeams = Set(defaults.stringArray(forKey: Self.nationalTeamsKey) ?? [])
        // Treat anyone who already follows a club as onboarded, so existing
        // users (and seeded simulators) don't get sent back through the picker.
        self.hasOnboarded = defaults.bool(forKey: Self.onboardedKey) || !saved.isEmpty
        migrateLegacyCompetitionFollows()
    }

    /// One-time: fold the old onboarding competition slugs into the real model, then
    /// clear them. USWNT/SheBelieves → follow the USA national team; CONCACAF → the
    /// Champions Cup toggle. WWC/Olympics have no home yet (whole-tournament UI is
    /// deferred), so they're dropped. Idempotent — once the legacy key is cleared,
    /// every later launch reads an empty array and no-ops.
    private func migrateLegacyCompetitionFollows() {
        let legacy = defaults.stringArray(forKey: Self.legacyCompetitionsKey) ?? []
        guard !legacy.isEmpty else { return }
        if legacy.contains("uswnt") || legacy.contains("shebelieves-cup") {
            followedNationalTeams.insert("USA")
            defaults.set(Array(followedNationalTeams), forKey: Self.nationalTeamsKey)
        }
        if legacy.contains("concacaf-w-champions") {
            isConcacafFollowed = true
            defaults.set(true, forKey: Self.concacafKey)
        }
        defaults.set([String](), forKey: Self.legacyCompetitionsKey)
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

    /// Replace the followed set wholesale (device-authoritative mirror reconcile on
    /// sign-in / new-device restore). Persists if changed; deliberately does NOT fire
    /// `onFollowsChanged` — FollowSyncCoordinator is the caller and reconciles the
    /// server itself. Replaces the old union `merge(ids:)`, which could only ADD, so
    /// an unfollow could never propagate and stale server rows accumulated forever.
    func replace(ids: Set<String>) {
        guard ids != followedIDs else { return }
        followedIDs = ids
        defaults.set(Array(followedIDs), forKey: Self.storageKey)
    }

    func isFollowing(nationalTeam team: NationalTeam) -> Bool {
        followedNationalTeams.contains(team.code)
    }

    /// Follow/unfollow a women's national team (by FIFA code); persists + signals the
    /// Schedule to refetch the national-team feeds.
    func toggle(nationalTeam team: NationalTeam) {
        if followedNationalTeams.contains(team.code) {
            followedNationalTeams.remove(team.code)
        } else {
            followedNationalTeams.insert(team.code)
        }
        defaults.set(Array(followedNationalTeams), forKey: Self.nationalTeamsKey)
        onCompetitionFollowsChanged?()
        onCompetitionFollowKeysChanged?(competitionFollowKeys)
    }

    /// Set the CONCACAF W Champions Cup global toggle; persists + signals the Schedule.
    func setConcacafFollowed(_ on: Bool) {
        guard on != isConcacafFollowed else { return }
        isConcacafFollowed = on
        defaults.set(on, forKey: Self.concacafKey)
        onCompetitionFollowsChanged?()
        onCompetitionFollowKeysChanged?(competitionFollowKeys)
    }

    // MARK: - Competition-follow sync surface

    /// The competition follows as a flat namespaced key set — "nt:<CODE>" per followed
    /// national team + "concacaf" when the Champions Cup is on. This is the exact shape
    /// stored in the `competition_follows` table, so the sync coordinator treats it just
    /// like the club follow set.
    var competitionFollowKeys: Set<String> {
        var keys = Set(followedNationalTeams.map { "nt:\($0)" })
        if isConcacafFollowed { keys.insert("concacaf") }
        return keys
    }

    /// Replace the competition follows wholesale from a key set (device-authoritative
    /// mirror reconcile). The twin of `replace(ids:)` for `competition_follows`:
    /// decodes the flat "nt:<CODE>" / "concacaf" keys back into the two stored fields,
    /// persists, and signals the Schedule if anything changed. Does NOT fire the sync
    /// closure — the coordinator is the caller and reconciles the server itself.
    func replaceCompetitionFollowKeys(_ keys: Set<String>) {
        let codes = Set(keys.filter { $0.hasPrefix("nt:") }.map { String($0.dropFirst(3)) })
        let concacaf = keys.contains("concacaf")
        guard codes != followedNationalTeams || concacaf != isConcacafFollowed else { return }
        followedNationalTeams = codes
        isConcacafFollowed = concacaf
        defaults.set(Array(followedNationalTeams), forKey: Self.nationalTeamsKey)
        defaults.set(isConcacafFollowed, forKey: Self.concacafKey)
        onCompetitionFollowsChanged?()
    }

    /// Mark onboarding finished (the "Follow N teams" button). One-way: once
    /// onboarded, Home always opens onto the hub, not the picker.
    func completeOnboarding() {
        let wasOnboarded = hasOnboarded
        hasOnboarded = true
        defaults.set(true, forKey: Self.onboardedKey)
        // Only on the real transition — re-calling this must not re-trigger a sync pass.
        if !wasOnboarded { onOnboardingCompleted?() }
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
        defaults.set([String](), forKey: legacyCompetitionsKey)
        defaults.set(false, forKey: onboardedKey)
        defaults.set(false, forKey: concacafKey)
        defaults.set([String](), forKey: nationalTeamsKey)
    }
    #endif
}
