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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Default-on for the high-signal alerts; off for the noisier ones (matches
        // the design's defaults). `object(forKey:)` so an unset pref takes the
        // default, not `bool(forKey:)`'s false.
        func load(_ key: String, default value: Bool) -> Bool {
            defaults.object(forKey: Self.prefix + key) as? Bool ?? value
        }
        dayBefore = load("dayBefore", default: true)
        lineupPosted = load("lineupPosted", default: true)
        kickoff = load("kickoff", default: true)
        goals = load("goals", default: true)
        halftime = load("halftime", default: false)
        fullTime = load("fullTime", default: true)
        substitutions = load("substitutions", default: false)
        fanZoneRounds = load("fanZoneRounds", default: true)
        playerSpotlight = load("playerSpotlight", default: true)
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
}
