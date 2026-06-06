//
//  TriviaStore.swift
//  NWSLApp
//
//  Durable Daily-Trivia stats — Home's Module 3 "Play", game 1 (per
//  Reference/Design/games-design-spec.md §Stats tracked). Like FollowingStore,
//  this is shared app state (the streak/score persist across launches and could
//  surface on more than one screen — the game itself today, the Home Play card
//  later), so it lives in Stores/ and is injected app-wide via `.environment`
//  in RootTabView, not owned by a single view.
//
//  Persistence is UserDefaults — a handful of scalars is a textbook fit, the
//  same call the spec makes ("streak and score tracked in UserDefaults"). The
//  in-progress session (current question, selection) is NOT here — that's
//  transient per-play state owned by TriviaViewModel. This store only holds what
//  must outlive a session: the streak, lifetime accuracy, and the day-gate.
//
//  The day-gate is the Wordle/Duolingo mechanic: one scored play per day. We key
//  off a local-day string ("2026-06-05"); completing today bumps the streak iff
//  the last completed day was *yesterday* (a gap resets it to 1). `now`/`calendar`
//  are injectable so tests can drive the clock deterministically.
//

import Foundation

@Observable
final class TriviaStore {
    /// Consecutive days the user has completed today's trivia (the streak).
    private(set) var streak: Int
    /// Longest streak ever reached — a durable "personal best" to show off.
    private(set) var bestStreak: Int

    /// Lifetime correct / answered, for all-time accuracy.
    private(set) var totalCorrect: Int
    private(set) var totalAnswered: Int

    /// Today's score (out of the day's question count). Only meaningful when
    /// `hasPlayedToday` — that's what the results screen shows on re-open.
    private(set) var lastScore: Int

    /// Local-day key ("yyyy-MM-dd") of the last completed play, or nil if never
    /// played. The day-gate and streak logic both key off this.
    private(set) var lastCompletedDay: String?

    private let defaults: UserDefaults
    private let calendar: Calendar
    private let now: () -> Date

    private enum Key {
        static let streak = "trivia.streak"
        static let bestStreak = "trivia.bestStreak"
        static let totalCorrect = "trivia.totalCorrect"
        static let totalAnswered = "trivia.totalAnswered"
        static let lastScore = "trivia.lastScore"
        static let lastCompletedDay = "trivia.lastCompletedDay"
    }

    /// `defaults`/`now`/`calendar` are injectable so tests (and previews) can use
    /// an isolated store and a fixed clock instead of the app's real state.
    init(
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
        self.streak = defaults.integer(forKey: Key.streak)
        self.bestStreak = defaults.integer(forKey: Key.bestStreak)
        self.totalCorrect = defaults.integer(forKey: Key.totalCorrect)
        self.totalAnswered = defaults.integer(forKey: Key.totalAnswered)
        self.lastScore = defaults.integer(forKey: Key.lastScore)
        self.lastCompletedDay = defaults.string(forKey: Key.lastCompletedDay)
    }

    // MARK: - Derived

    /// True once today's trivia is done — the day-gate that locks replay until
    /// tomorrow (the streak mechanic, per the approved replay rule).
    var hasPlayedToday: Bool {
        lastCompletedDay == dayKey(for: now())
    }

    /// Lifetime accuracy as a fraction 0…1 (0 when nothing's been answered).
    var accuracy: Double {
        totalAnswered == 0 ? 0 : Double(totalCorrect) / Double(totalAnswered)
    }

    // MARK: - Mutation

    /// Commit a finished session: bump the streak, fold the score into lifetime
    /// accuracy, and stamp today as played. Idempotent for the day — calling it
    /// again after `hasPlayedToday` does nothing, so a re-open can't farm the
    /// streak or double-count accuracy.
    func recordCompletion(correct: Int, outOf total: Int) {
        guard !hasPlayedToday else { return }

        let today = dayKey(for: now())
        // Streak continues only if the previous completion was *yesterday*;
        // any gap (or a first-ever play) restarts it at 1.
        if let last = lastCompletedDay, last == dayKey(for: yesterday()) {
            streak += 1
        } else {
            streak = 1
        }
        bestStreak = max(bestStreak, streak)

        totalCorrect += correct
        totalAnswered += total
        lastScore = correct
        lastCompletedDay = today

        persist()
    }

    // MARK: - Helpers

    private func persist() {
        defaults.set(streak, forKey: Key.streak)
        defaults.set(bestStreak, forKey: Key.bestStreak)
        defaults.set(totalCorrect, forKey: Key.totalCorrect)
        defaults.set(totalAnswered, forKey: Key.totalAnswered)
        defaults.set(lastScore, forKey: Key.lastScore)
        defaults.set(lastCompletedDay, forKey: Key.lastCompletedDay)
    }

    /// Start of "the day before now," for the streak's yesterday check.
    private func yesterday() -> Date {
        calendar.date(byAdding: .day, value: -1, to: now()) ?? now()
    }

    /// A stable local-day key ("yyyy-MM-dd") in the calendar's time zone, so the
    /// day-gate flips at local midnight regardless of locale.
    private func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
