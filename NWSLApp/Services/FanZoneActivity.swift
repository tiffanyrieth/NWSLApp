//
//  FanZoneActivity.swift
//  NWSLApp
//
//  A tiny cross-game weekly-play ledger (Competitive Redesign, PR4) — the backing for the "Iron Fan"
//  achievement (play a Fan Zone game every week for 4 consecutive weeks). Each game records a play on
//  commit; detection counts consecutive weeks back from now. Deliberately NOT an @Observable store (it's a
//  detection ledger, not UI state) — a handful of week ordinals in UserDefaults. Injectable clock/defaults
//  for tests.
//
//  Weeks are absolute ordinals (whole weeks since the Unix epoch), not ISO weeks — monotonic and
//  gap-free across year boundaries, which is all "consecutive" needs (the epoch-was-a-Thursday ISO
//  reconstruction trap doesn't apply to plain subtraction).
//

import Foundation

enum FanZoneActivity {
    private static let key = "fanzone.activity.weeks"
    private static let secondsPerWeek: TimeInterval = 7 * 24 * 60 * 60

    /// The absolute week ordinal for a date (weeks since the epoch).
    static func weekOrdinal(_ date: Date) -> Int {
        Int(date.timeIntervalSince1970 / secondsPerWeek)
    }

    /// Record that the user played a Fan Zone game this week (idempotent within a week). Call on any game
    /// commit (submit / round completion).
    static func recordPlay(now: Date = Date(), defaults: UserDefaults = .standard) {
        var weeks = Set(defaults.array(forKey: key) as? [Int] ?? [])
        weeks.insert(weekOrdinal(now))
        defaults.set(Array(weeks), forKey: key)
    }

    /// How many consecutive weeks (including the current one) the user has played — counting back from now
    /// while each week is present. 0 if this week hasn't been played.
    static func consecutiveWeeksPlayed(now: Date = Date(), defaults: UserDefaults = .standard) -> Int {
        let weeks = Set(defaults.array(forKey: key) as? [Int] ?? [])
        var week = weekOrdinal(now)
        var streak = 0
        while weeks.contains(week) {
            streak += 1
            week -= 1
        }
        return streak
    }

    #if DEBUG
    static func debugReset(defaults: UserDefaults = .standard) { defaults.removeObject(forKey: key) }
    #endif
}
