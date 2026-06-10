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

@Observable
final class NotificationPreferencesStore {
    // MARK: Match Day
    var dayBefore: Bool      { didSet { persist(dayBefore, "dayBefore") } }
    var lineupPosted: Bool   { didSet { persist(lineupPosted, "lineupPosted") } }
    var kickoff: Bool        { didSet { persist(kickoff, "kickoff") } }
    var goals: Bool          { didSet { persist(goals, "goals") } }
    var halftime: Bool       { didSet { persist(halftime, "halftime") } }
    var fullTime: Bool       { didSet { persist(fullTime, "fullTime") } }
    var substitutions: Bool  { didSet { persist(substitutions, "substitutions") } }

    // MARK: Activity
    var fanZoneRounds: Bool  { didSet { persist(fanZoneRounds, "fanZoneRounds") } }
    var playerSpotlight: Bool { didSet { persist(playerSpotlight, "playerSpotlight") } }

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
}
