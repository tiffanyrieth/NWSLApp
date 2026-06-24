//
//  TeamAlertStore.swift
//  NWSLApp
//
//  Which teams buzz your phone on match day (QOL v2: Follow vs Alerts). Following a
//  club (⭐, FollowingStore) and getting match alerts for it (🔔, this) are
//  independent. Per-team is a simple ON/OFF switch — WHAT you're alerted about
//  (kickoff, goals, …) is a GLOBAL choice in NotificationPreferencesStore, applied to
//  every team with alerts on. So this store is just a set of team ids.
//
//  Same idiom as FollowingStore: an @Observable Store injected via `.environment`,
//  persisted to UserDefaults, keyed by ESPN team id (lines up with
//  FollowingStore.followedIDs + Supabase `follows.team_id`). Network-ignorant —
//  TeamAlertSyncCoordinator arms `onAlertChanged` after sign-in to mirror edits to
//  Supabase, exactly as FollowSyncCoordinator does with FollowingStore.
//

import Foundation

@Observable
final class TeamAlertStore {
    /// Team ids with match alerts ON. Read-only outside; mutate through the methods
    /// below so persistence + the change seam stay in sync.
    private(set) var enabledTeamIDs: Set<String>

    /// Fired after a real on/off change, with the team id + its new state. Optional
    /// and nil by default; TeamAlertSyncCoordinator sets it to push the change up.
    /// Not fired during `init` (property load, not an edit).
    var onAlertChanged: ((String, Bool) -> Void)?

    private let defaults: UserDefaults
    private static let storageKey = "teamAlerts.enabledIDs.v2"
    private static let migratedKey = "teamAlerts.migrated.v2"

    /// `defaults` is injectable so tests (and previews) use an isolated store.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.enabledTeamIDs = Set(defaults.stringArray(forKey: Self.storageKey) ?? [])
    }

    private func persist() {
        defaults.set(Array(enabledTeamIDs), forKey: Self.storageKey)
    }

    // MARK: - Reads

    func alertsEnabled(for teamID: String) -> Bool {
        enabledTeamIDs.contains(teamID)
    }

    var enabledCount: Int { enabledTeamIDs.count }

    func teamsWithAlerts() -> Set<String> { enabledTeamIDs }

    // MARK: - Writes

    /// Turn a team's alerts on/off; persists + notifies only on a real change (so a
    /// no-op set doesn't echo to Supabase).
    func setAlertsEnabled(_ enabled: Bool, for teamID: String) {
        let changed: Bool
        if enabled { changed = enabledTeamIDs.insert(teamID).inserted }
        else { changed = enabledTeamIDs.remove(teamID) != nil }
        guard changed else { return }
        persist()
        onAlertChanged?(teamID, enabled)
    }

    func toggle(for teamID: String) {
        setAlertsEnabled(!alertsEnabled(for: teamID), for: teamID)
    }

    /// Clear a team's alerts — used when it leaves the followed set (alerts require
    /// following). No-op (no seam fire) if it had none, so unfollowing a never-alerted
    /// team is silent.
    func clearAlerts(for teamID: String) {
        setAlertsEnabled(false, for: teamID)
    }

    /// Replace the local ON set wholesale (device-authoritative mirror reconcile on
    /// sign-in). Persists if changed; deliberately does NOT fire `onAlertChanged` —
    /// TeamAlertSyncCoordinator is the caller and reconciles the server itself
    /// (pushing the kept teams, deleting the rest). Replaces the old union-merge,
    /// which could only ever ADD, so stale server rows accumulated forever.
    func replaceEnabled(_ newSet: Set<String>) {
        guard newSet != enabledTeamIDs else { return }
        enabledTeamIDs = newSet
        persist()
    }

    // MARK: - Migration

    /// One-time seed from the old GLOBAL match-day toggles, so a 0.3.9 upgrader keeps
    /// their alerts. Per the owner's rule: a followed team gets alerts ON only if the
    /// user actually had any match-day alert on globally — otherwise everyone would
    /// suddenly start buzzing. Self-guards on a sentinel (runs once, never clobbers
    /// later edits); safe to call every launch.
    func migrateFromGlobalIfNeeded(
        global: NotificationPreferencesSnapshot,
        followedIDs: Set<String>
    ) {
        guard !defaults.bool(forKey: Self.migratedKey) else { return }
        let hadAlerts = global.dayBefore || global.kickoff || global.goals
            || global.halftime || global.fullTime
        if hadAlerts {
            enabledTeamIDs.formUnion(followedIDs)
            persist()
        }
        defaults.set(true, forKey: Self.migratedKey)
    }

    #if DEBUG
    /// Dev-only: clear all per-team match-alert state so `-resetOnboarding` reproduces a
    /// brand-new install (no phantom "N teams with match alerts" footer left over from a
    /// prior session — Part B Bug 2). Static + key-aware so it runs before any instance
    /// exists, in `NWSLAppApp.init()`. Writes cleared sentinels (not `removeObject`) for
    /// the same CFPreferences-snapshot reason as `FollowingStore.debugResetState()`.
    static func debugResetState(defaults: UserDefaults = .standard) {
        defaults.set([String](), forKey: storageKey)
        defaults.set(false, forKey: migratedKey)
    }
    #endif
}
