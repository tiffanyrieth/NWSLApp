//
//  TriviaStore.swift
//  NWSLApp
//
//  Durable NWSL Trivia stats — the community-family quiz alongside Know Her Game.
//  Like FollowingStore, this is shared app state (the streak/score persist across
//  launches and surface on more than one screen), so it lives in Stores/ and is
//  injected app-wide via `.environment` in RootTabView, not owned by a single view.
//
//  ROUND MODEL (2026-07-23, replaces the daily Wordle-style gate): Trivia runs in
//  BIWEEKLY ROUNDS — 10 questions per round, a new round every two weeks on the
//  Trivia drop week (`FanZoneCadence`, staggered against Know Her Game so one
//  community game refreshes every week). One scored play per ROUND; the streak
//  counts consecutive ROUNDS played. The round structure ships ahead of the
//  content pipeline on purpose (owner: build toward the future) — the biweekly
//  question generation rides the existing pool until the annual-regen routine lands.
//
//  RETENTION (owner rule): the store keeps per-round results for the CURRENT and
//  PREVIOUS round only — the landing page can review "last round" (score + community
//  recap) and nothing older. Lifetime/season counters are aggregates, not history,
//  so they survive pruning. Server-side, `quiz_answers` follows the same rule via
//  the retention cron.
//
//  Persistence is UserDefaults — a handful of scalars + two tiny pruned dictionaries.
//  The in-progress session (current question, selection) is NOT here — that's
//  transient per-play state owned by TriviaViewModel.
//
//  Migration from the daily model: lifetime counters (`totalCorrect` etc.) carry
//  over untouched — they were always play-count-agnostic. `bestStreak` carries
//  NUMERICALLY (a 12-day best reads as a 12-round best — generous but honest as a
//  personal-best plaque; resetting a fan's best to 0 is worse). The CURRENT streak
//  starts fresh at 0 under new keys: showing a 12-DAY streak as "12-round streak"
//  would be a live lie, and the first round completion restarts it at 1 anyway.
//

import Foundation

@Observable
final class TriviaStore {
    /// Consecutive ROUNDS completed (the streak). Continues iff the previous
    /// completion was the immediately-prior round; a missed round resets to 1.
    private(set) var streak: Int
    /// Longest streak ever reached — a durable "personal best" to show off.
    private(set) var bestStreak: Int

    /// Lifetime correct / answered, for all-time accuracy.
    private(set) var totalCorrect: Int
    private(set) var totalAnswered: Int

    /// Correct answers in the CURRENT NWSL season only (zeroes at the season boundary), for the season-
    /// scoped Superfan total — which never combines years. Distinct from lifetime `totalCorrect`.
    private(set) var seasonCorrect: Int
    /// The season `seasonCorrect` belongs to; a new season zeroes the counter.
    private var counterSeason: Int

    /// editionKey ("2026-R08") → score, for the CURRENT + PREVIOUS round only (pruned on write).
    /// Present ⇒ that round was completed. The landing page's "This round"/"Last round" states and
    /// the review recap read these.
    private(set) var roundScores: [String: Int]
    /// editionKey → the option picked per question, same retention as `roundScores`. Lets the
    /// last-round community recap highlight the user's own answers (the questions themselves are NOT
    /// stored — they recompute deterministically from the pool + round number).
    private(set) var roundPicks: [String: [Int]]

    /// The round ordinal of the most recent completion (0 = never played a round).
    /// Drives streak adjacency across the biweekly cadence.
    private(set) var lastCompletedRound: Int

    private let defaults: UserDefaults
    private let calendar: Calendar
    private let now: () -> Date

    private enum Key {
        // Round-model keys (new)
        static let roundStreak = "trivia.roundStreak"
        static let roundScores = "trivia.roundScores"
        static let roundPicks = "trivia.roundPicks"
        static let lastCompletedRound = "trivia.lastCompletedRound"
        // Carried over from the daily model unchanged
        static let bestStreak = "trivia.bestStreak"
        static let totalCorrect = "trivia.totalCorrect"
        static let totalAnswered = "trivia.totalAnswered"
        static let seasonCorrect = "trivia.seasonCorrect"
        static let counterSeason = "trivia.counterSeason"
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
        self.streak = defaults.integer(forKey: Key.roundStreak)
        self.bestStreak = defaults.integer(forKey: Key.bestStreak)
        self.totalCorrect = defaults.integer(forKey: Key.totalCorrect)
        self.totalAnswered = defaults.integer(forKey: Key.totalAnswered)
        self.seasonCorrect = defaults.integer(forKey: Key.seasonCorrect)
        self.counterSeason = defaults.integer(forKey: Key.counterSeason)
        self.lastCompletedRound = defaults.integer(forKey: Key.lastCompletedRound)
        self.roundScores = Self.decodeDict(defaults.data(forKey: Key.roundScores)) ?? [:]
        self.roundPicks = Self.decodeDict(defaults.data(forKey: Key.roundPicks)) ?? [:]
        // One-time seed when the season counter is first added (season 1): all lifetime correct IS this
        // season's (no prior year exists yet), so the season-scoped Superfan total doesn't undercount
        // pre-migration play. (`self` is fully initialized here, so `seasonNow` is usable.)
        if defaults.object(forKey: Key.counterSeason) == nil {
            counterSeason = seasonNow
            seasonCorrect = totalCorrect
            defaults.set(seasonCorrect, forKey: Key.seasonCorrect)
            defaults.set(counterSeason, forKey: Key.counterSeason)
        }
    }

    // MARK: - Round context (the store's own clock → the shared cadence)

    /// The live Trivia round number right now (nil only before Trivia's first-ever round).
    var currentRound: Int? { FanZoneCadence.roundNumber(for: .trivia, at: now()) }

    /// The edition key for the live round — the `quiz_answers` edition and the local results key.
    var currentEditionKey: String? {
        currentRound.map { FanZoneCadence.editionKey(round: $0, seasonYear: FanZoneCadence.seasonYear) }
    }

    /// The immediately-prior round's edition key (nil during round 1).
    var previousEditionKey: String? {
        guard let round = currentRound, round > 1 else { return nil }
        return FanZoneCadence.editionKey(round: round - 1, seasonYear: FanZoneCadence.seasonYear)
    }

    /// When the live round closes (the landing page's "closes in N days").
    var roundCloses: Date { FanZoneCadence.roundCloses(for: .trivia, at: now()) }

    // MARK: - Derived

    /// True once the LIVE round is completed — locks replay until the next round drops.
    var hasPlayedCurrentRound: Bool {
        guard let key = currentEditionKey else { return false }
        return roundScores[key] != nil
    }

    /// The live round's banked score (nil until played).
    var currentScore: Int? { currentEditionKey.flatMap { roundScores[$0] } }

    /// Last round's banked score (nil if it wasn't played — the honest "didn't play" state).
    var previousScore: Int? { previousEditionKey.flatMap { roundScores[$0] } }

    func isPlayed(editionKey: String) -> Bool { roundScores[editionKey] != nil }
    func score(editionKey: String) -> Int? { roundScores[editionKey] }
    func picks(editionKey: String) -> [Int]? { roundPicks[editionKey] }

    /// Lifetime accuracy as a fraction 0…1 (0 when nothing's been answered).
    var accuracy: Double {
        totalAnswered == 0 ? 0 : Double(totalCorrect) / Double(totalAnswered)
    }

    /// Whether the user has ever completed a round/day of Trivia (feeds the Game Center
    /// "played all three" achievement — play under the old daily model still counts).
    var hasEverPlayed: Bool { totalAnswered > 0 }

    // MARK: - Mutation

    /// Bank a finished round: bump the round streak, fold the score into lifetime + season
    /// accuracy, and stamp the round played. Idempotent per round — calling it again for a
    /// completed round does nothing, so a re-open can't farm the streak or double-count.
    func recordCompletion(round: Int, editionKey: String, correct: Int, outOf total: Int, picks: [Int]) {
        guard roundScores[editionKey] == nil else { return }

        // Streak continues only if the previous completion was the immediately-prior round;
        // any gap (or a first-ever play) restarts it at 1.
        if lastCompletedRound > 0,
           FanZoneCadence.isConsecutiveRound(previous: lastCompletedRound, current: round) {
            streak += 1
        } else {
            streak = 1
        }
        bestStreak = max(bestStreak, streak)

        totalCorrect += correct
        totalAnswered += total
        // Season-scoped counter (the Superfan total never combines years): a new season zeroes it first.
        let season = seasonNow
        if counterSeason != season { seasonCorrect = 0; counterSeason = season }
        seasonCorrect += correct

        roundScores[editionKey] = correct
        roundPicks[editionKey] = picks
        lastCompletedRound = round
        pruneToLastTwoRounds()

        persist()
    }

    // MARK: - Progress restore (ProgressSyncService — reinstall / replacement phone)

    /// This store's contribution to the per-user summary row.
    func progressSnapshot() -> (lifetimeCorrect: Int, lifetimeAnswered: Int, bestStreak: Int,
                                seasonCorrect: Int, roundStreak: Int, lastRound: Int) {
        (totalCorrect, totalAnswered, bestStreak, seasonCorrect, streak, lastCompletedRound)
    }

    /// Fold a MERGED snapshot back in at sign-in (ProgressSnapshot.merge already resolved which side
    /// wins, monotonically — so this only ever raises counters / adopts a fresher streak pair; a
    /// fresh install simply takes the server values). Per-round scores/picks are NOT restored: they
    /// are pruned history (retention rule), and the community recap works without them.
    func restoreProgress(lifetimeCorrect: Int, lifetimeAnswered: Int, bestStreak restoredBest: Int,
                         seasonCorrect restoredSeason: Int, roundStreak: Int, lastRound: Int) {
        totalCorrect = max(totalCorrect, lifetimeCorrect)
        totalAnswered = max(totalAnswered, lifetimeAnswered)
        bestStreak = max(bestStreak, restoredBest)
        seasonCorrect = max(seasonCorrect, restoredSeason)
        if lastRound > lastCompletedRound {
            streak = roundStreak
            lastCompletedRound = lastRound
        }
        persist()
    }

    /// Owner retention rule: current + previous round only. Keys are zero-padded ("2026-R08"),
    /// so lexical order == chronological order, including across a season boundary
    /// ("2027-R01" > "2026-R26") — keep the two largest, drop the rest.
    private func pruneToLastTwoRounds() {
        let keep = Set(roundScores.keys.sorted().suffix(2))
        roundScores = roundScores.filter { keep.contains($0.key) }
        roundPicks = roundPicks.filter { keep.contains($0.key) }
    }

    // MARK: - Helpers

    private func persist() {
        defaults.set(streak, forKey: Key.roundStreak)
        defaults.set(bestStreak, forKey: Key.bestStreak)
        defaults.set(totalCorrect, forKey: Key.totalCorrect)
        defaults.set(totalAnswered, forKey: Key.totalAnswered)
        defaults.set(seasonCorrect, forKey: Key.seasonCorrect)
        defaults.set(counterSeason, forKey: Key.counterSeason)
        defaults.set(lastCompletedRound, forKey: Key.lastCompletedRound)
        defaults.set(try? JSONEncoder().encode(roundScores), forKey: Key.roundScores)
        defaults.set(try? JSONEncoder().encode(roundPicks), forKey: Key.roundPicks)
    }

    private static func decodeDict<V: Decodable>(_ data: Data?) -> [String: V]? {
        data.flatMap { try? JSONDecoder().decode([String: V].self, from: $0) }
    }

    /// The current NWSL season year from the injectable clock (Jan/Feb still counts as the prior year).
    private var seasonNow: Int {
        let year = calendar.component(.year, from: now())
        return calendar.component(.month, from: now()) < 3 ? year - 1 : year
    }

    /// Wipe all local Trivia progress on account deletion — resets the in-memory
    /// @Observable state AND persistence (so the UI reflects the wipe immediately).
    /// The server rows are removed by the account-delete cascade; this
    /// clears the on-device cache so "delete account" truly forgets you.
    func resetForAccountDeletion() {
        streak = 0
        bestStreak = 0
        totalCorrect = 0
        totalAnswered = 0
        seasonCorrect = 0
        counterSeason = 0
        roundScores = [:]
        roundPicks = [:]
        lastCompletedRound = 0
        persist()
    }

    #if DEBUG
    /// Dev-only: wipe Trivia progress so `-resetOnboarding` simulates a brand-new
    /// install (see NWSLAppApp.init). Static + key-name-aware so it runs before any
    /// store instance exists. Local-only: the server rows are untouched
    /// (additive history, like AuthStore.deleteAccount), and nothing syncs them back
    /// down into this store, so the wipe sticks.
    ///
    /// Writes cleared SENTINELS (0 / empty) rather than `removeObject`, matching
    /// FollowingStore.debugResetState: at App.init timing in the Simulator a key
    /// *deletion* doesn't reliably propagate against cfprefsd's snapshot (a seeded
    /// value reads back stale), but an explicit write always takes.
    static func debugResetState(defaults: UserDefaults = .standard) {
        defaults.set(0, forKey: Key.roundStreak)
        defaults.set(0, forKey: Key.bestStreak)
        defaults.set(0, forKey: Key.totalCorrect)
        defaults.set(0, forKey: Key.totalAnswered)
        defaults.set(0, forKey: Key.lastCompletedRound)
        defaults.set(Data(), forKey: Key.roundScores)
        defaults.set(Data(), forKey: Key.roundPicks)
    }
    #endif
}
