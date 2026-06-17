//
//  NotificationPreferencesStore.swift
//  NWSLApp
//
//  The user's notification preferences — the 9 toggles on the Profile screen
//  (Match Day + Activity). Shared app-wide state persisted to UserDefaults and
//  injected via `.environment`, mirroring FeedPreferencesStore.
//
//  TEMP (no delivery yet): these toggles persist the user's *intent* only. Actual
//  notifications need APNs + the server poller (live updates) or local scheduling
//  (kickoff reminders) — see CLAUDE.md What's-Next #12. When that lands, the
//  scheduler reads these same flags; nothing here changes.
//

import Foundation

/// A plain value snapshot of all nine toggles — the shape that mirrors up to the
/// Supabase `notification_preferences` row so the match-watcher Worker can honor
/// "goals: off" without asking the device. Kept SDK-free (no Supabase import) so
/// the store stays pure; NotificationPrefsSyncService maps it to/from the row.
struct NotificationPreferencesSnapshot: Equatable {
    var dayBefore: Bool
    var lineupPosted: Bool
    var kickoff: Bool
    var goals: Bool
    var halftime: Bool
    var fullTime: Bool
    var substitutions: Bool
    var fanZoneRounds: Bool
    var playerSpotlight: Bool
}

@Observable
final class NotificationPreferencesStore {
    // MARK: Match Day
    var dayBefore: Bool      { didSet { persist(dayBefore, "dayBefore"); onPreferenceChanged?() } }
    var lineupPosted: Bool   { didSet { persist(lineupPosted, "lineupPosted"); onPreferenceChanged?() } }
    var kickoff: Bool        { didSet { persist(kickoff, "kickoff"); onPreferenceChanged?() } }
    var goals: Bool          { didSet { persist(goals, "goals"); onPreferenceChanged?() } }
    var halftime: Bool       { didSet { persist(halftime, "halftime"); onPreferenceChanged?() } }
    var fullTime: Bool       { didSet { persist(fullTime, "fullTime"); onPreferenceChanged?() } }
    var substitutions: Bool  { didSet { persist(substitutions, "substitutions"); onPreferenceChanged?() } }

    // MARK: Activity
    var fanZoneRounds: Bool  { didSet { persist(fanZoneRounds, "fanZoneRounds"); onPreferenceChanged?() } }
    var playerSpotlight: Bool { didSet { persist(playerSpotlight, "playerSpotlight"); onPreferenceChanged?() } }

    /// Whether the user has visited the Notifications hub at least once. The per-team
    /// bells no longer gate on this (the Teams-tab coach mark replaced the old
    /// "doorway" — bells now toggle directly); it survives only to make the one-time
    /// auth-aware Tier-2 default establishment in `markHubVisited(isSignedIn:)`
    /// idempotent. Persisted under the spec key `notifications.hubVisited`; set via
    /// `markHubVisited(isSignedIn:)` from the hub's `onAppear`.
    private(set) var hubVisited: Bool

    /// All nine toggles as a value snapshot. Reading it touches every flag, so it
    /// also doubles as the single property NotificationSyncCoordinator observes via
    /// withObservationTracking to mirror any change up to Supabase.
    var snapshot: NotificationPreferencesSnapshot {
        NotificationPreferencesSnapshot(
            dayBefore: dayBefore,
            lineupPosted: lineupPosted,
            kickoff: kickoff,
            goals: goals,
            halftime: halftime,
            fullTime: fullTime,
            substitutions: substitutions,
            fanZoneRounds: fanZoneRounds,
            playerSpotlight: playerSpotlight
        )
    }

    /// Fired after any toggle changes, so the NotificationScheduler can rebuild
    /// local notifications. Optional and nil by default — when nil (no scheduler
    /// wired, tests, previews) the store behaves exactly as before. Mirrors
    /// FollowingStore.onFollowsChanged. Property observers don't run during `init`,
    /// so loading persisted defaults never fires this.
    var onPreferenceChanged: (() -> Void)?

    private let defaults: UserDefaults
    private static let prefix = "notif."
    // The hub-visited flag uses the spec-named key (not the `notif.` prefix), per
    // Bell-Tap First-Time Flow Fix.md.
    private static let hubVisitedKey = "notifications.hubVisited"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // `object(forKey:)` so an unset pref takes the default, not `bool(forKey:)`'s
        // false. Invariant (QOL v2 / Bell-Tap fix): **Tier 2 ON ⟹ signed in**. The
        // baked init defaults therefore keep every Tier-2 SERVER-PUSH type (kickoff,
        // goals, halftime, full-time + the not-yet-surfaced lineup/subs) OFF — a
        // signed-out (first-run) user can't receive them, so defaulting them on would
        // be a lie. Only the Tier-1 LOCAL types default ON (they deliver signed-out).
        // A signed-IN user gets the Tier-2 types defaulted ON on first hub visit (see
        // `markHubVisited(isSignedIn:)`). Sign-out forces them back OFF
        // (`resetServerPushTypes()`); turning one on signed-out hits the hub gate.
        func load(_ key: String, default value: Bool) -> Bool {
            defaults.object(forKey: Self.prefix + key) as? Bool ?? value
        }
        dayBefore = load("dayBefore", default: true)          // Tier 1 (local)
        playerSpotlight = load("playerSpotlight", default: true)  // Tier 1 (local)
        fanZoneRounds = load("fanZoneRounds", default: true)  // activity (local intent)
        kickoff = load("kickoff", default: false)             // Tier 2 (server push)
        goals = load("goals", default: false)                 // Tier 2 (server push)
        halftime = load("halftime", default: false)           // Tier 2 (server push)
        fullTime = load("fullTime", default: false)           // Tier 2 (server push)
        lineupPosted = load("lineupPosted", default: false)   // Tier 2 (server, Stage D)
        substitutions = load("substitutions", default: false) // Tier 2 (server, Stage D)
        hubVisited = defaults.bool(forKey: Self.hubVisitedKey)
    }

    /// Record the first visit to the Notifications hub. On that FIRST visit only, it
    /// establishes the auth-aware Tier-2 defaults: a signed-IN user gets the live-match
    /// types
    /// (kickoff/goals/halftime/full-time) defaulted ON; a signed-OUT user keeps them
    /// OFF (upholding `Tier 2 ON ⟹ signed in` — they opt in later via the hub's
    /// sign-in gate). Idempotent. Not a `didSet` property so loading the flag in
    /// `init` never fires this.
    func markHubVisited(isSignedIn: Bool) {
        guard !hubVisited else { return }
        hubVisited = true
        defaults.set(true, forKey: Self.hubVisitedKey)
        if isSignedIn {
            kickoff = true
            goals = true
            halftime = true
            fullTime = true
        }
    }

    private func persist(_ value: Bool, _ key: String) {
        defaults.set(value, forKey: Self.prefix + key)
    }

    /// Turn off every Tier-2 (server-push) alert type — kickoff, goals, halftime,
    /// full-time. Called on sign-out: these can't be delivered without an account
    /// (the APNs token is detached too), so leaving them "on" would be a lie. The
    /// Tier-1 locals (day-before, Player Spotlight) stay — they work signed-out. On
    /// sign-in the user re-enables Tier-2 from the hub with no gate (they're signed
    /// in now). Each setter persists + fires `onPreferenceChanged`.
    func resetServerPushTypes() {
        kickoff = false
        goals = false
        halftime = false
        fullTime = false
    }

    #if DEBUG
    /// Wipe notification first-run state so `-resetOnboarding` simulates a brand-NEW
    /// user. Clears every toggle (so `init` re-applies the fresh defaults — Tier-1 ON,
    /// Tier-2 OFF), `hubVisited` (which now only keeps Tier-2 default establishment
    /// idempotent), and the Teams-tab match-alert coach mark so it re-fires. Mirrors
    /// `FollowingStore.debugResetState`; runs (from `NWSLAppApp.init`) before the store
    /// is constructed.
    static func debugResetState(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: hubVisitedKey)
        // The one-time Teams-tab "Manage your match alerts here" coach mark
        // (TeamsView @AppStorage) — clear so a reset re-shows it for a true new user.
        defaults.removeObject(forKey: "hasSeenTeamsAlertTooltip")
        for key in ["dayBefore", "playerSpotlight", "fanZoneRounds", "kickoff", "goals",
                    "halftime", "fullTime", "lineupPosted", "substitutions"] {
            defaults.removeObject(forKey: prefix + key)
        }
    }
    #endif
}
