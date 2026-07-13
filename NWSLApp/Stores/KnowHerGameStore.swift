//
//  KnowHerGameStore.swift
//  NWSLApp
//
//  Durable Know Her Game state — the Fan Zone weekly player quiz (docs/know-her-game.md).
//  Like TriviaStore / PredictionStore, this is shared app state injected app-wide via
//  `.environment` in RootTabView: the game screen, the Home Fan Zone card, and the picker
//  all read the same played/score state and the same in-memory weekly pool.
//
//  Two halves:
//   • DURABLE (UserDefaults, `knowher.v1.*`): per-edition scores keyed by
//     "{weekKey}-{team}-{athleteId}" (mirror PredictionStore's per-fixture keying) + a
//     WEEKLY streak (§14 — completing ≥1 player in a Mon–Sun window counts).
//   • IN-MEMORY: the fetched `KnowHerPool` for the followed teams (like BracketStore.summary),
//     loaded via KnowHerService. Drives the Home card + visibility gate + the picker.
//
//  One attempt, no partial saves (docs §2): a completed edition banks its score and never
//  replays; quitting mid-game discards (the view model owns the transient session).
//

import Foundation

@Observable
final class KnowHerGameStore {
    /// editionKey ("{weekKey}-{team}-{athleteId}") → score (correct count). Present ⇒ completed.
    private(set) var scores: [String: Int]

    /// Weekly streak (§14): consecutive Mon–Sun windows in which ≥1 player was completed.
    private(set) var weeklyStreak: Int
    private(set) var bestWeeklyStreak: Int
    /// The `weekKey` of the last completed week, for the streak's continuity check.
    private(set) var lastCompletedWeek: String?

    // In-memory pool (not persisted — refetched each session, online-only).
    enum LoadState { case idle, loading, loaded, error(String) }
    private(set) var loadState: LoadState = .idle
    private(set) var pool: KnowHerPool?

    /// The immediately-prior week's pool, kept so the picker's "Last week" section can show that
    /// edition's FINAL community results (and your score, if you played). PERSISTED (unlike the current
    /// pool) because the proxy only serves the CURRENT week — without a local copy we'd have no question
    /// text to render last week's breakdown. Held only while it's exactly one ISO week behind the current
    /// pool (see `loadIfNeeded`); a staler pool is dropped so "Last week" never lies.
    private(set) var previousPool: KnowHerPool?

    private let defaults: UserDefaults
    private let service: KnowHerService

    private enum Key {
        static let scores = "knowher.v1.scores"
        static let weeklyStreak = "knowher.v1.weeklyStreak"
        static let bestWeeklyStreak = "knowher.v1.bestWeeklyStreak"
        static let lastCompletedWeek = "knowher.v1.lastCompletedWeek"
        static let previousPool = "knowher.v1.previousPool"
    }

    init(defaults: UserDefaults = .standard, service: KnowHerService = KnowHerService()) {
        self.defaults = defaults
        self.service = service
        self.scores = Self.decode([String: Int].self, defaults.data(forKey: Key.scores)) ?? [:]
        self.weeklyStreak = defaults.integer(forKey: Key.weeklyStreak)
        self.bestWeeklyStreak = defaults.integer(forKey: Key.bestWeeklyStreak)
        self.lastCompletedWeek = defaults.string(forKey: Key.lastCompletedWeek)
        self.previousPool = Self.decode(KnowHerPool.self, defaults.data(forKey: Key.previousPool))
    }

    // MARK: - Loading (in-memory pool)

    /// Fetch the weekly pool for the followed teams. Idempotent-ish: skips when already loaded
    /// for the same team set unless `force`. Online-only — a failure/empty pool sets `.error`
    /// and the game hides (the Home gate checks `hasContent`). Runs on the main actor (the
    /// @Observable store is UI-facing).
    @MainActor
    func loadIfNeeded(teams: [String], force: Bool = false) async {
        if case .loading = loadState { return }
        if !force, case .loaded = loadState, pool != nil { return }
        guard !teams.isEmpty else {
            pool = nil
            loadState = .loaded            // no followed teams → no content, not an error
            return
        }
        loadState = .loading
        do {
            let fetched = try await service.pool(teams: teams)
            rotatePreviousPool(oldPool: pool, newPool: fetched)
            pool = fetched
            loadState = .loaded
        } catch {
            pool = nil
            loadState = .error("Couldn't load Know Her Game — tap to retry.")
            Diagnostics.shared.record(.apiFailure, "knowher load: \(error.localizedDescription)")
        }
    }

    /// Maintain the one-week "Last week" window. When a NEW week's pool arrives, the pool we were showing
    /// becomes "last week" — but only if it's EXACTLY the prior ISO week (reusing the streak's
    /// week-adjacency check); a 2-week-stale pool (app not opened in a while) is dropped so the section
    /// never mislabels an old edition. Same-week reloads and the very first load don't rotate.
    private func rotatePreviousPool(oldPool: KnowHerPool?, newPool: KnowHerPool) {
        guard let oldPool, oldPool.weekKey != newPool.weekKey else { return } // same-week reload / first load
        previousPool = Self.retainsPreviousWeek(old: oldPool.weekKey, new: newPool.weekKey) ? oldPool : nil
        defaults.set(try? JSONEncoder().encode(previousPool), forKey: Key.previousPool)
    }

    /// Whether the outgoing week should be KEPT as "last week": a different week AND exactly the prior
    /// ISO week (a 2-week gap — app not opened in a while — is dropped so the section never mislabels).
    static func retainsPreviousWeek(old: String, new: String) -> Bool {
        old != new && isConsecutiveWeek(previous: old, current: new)
    }

    // MARK: - Reads

    /// The week key of the loaded pool (nil until loaded). Keys played state + editions.
    var weekKey: String? { pool?.weekKey }

    /// The featured players for the followed teams, in the pool's order.
    var players: [KnowHerPlayer] { pool?.players ?? [] }

    /// True once there's at least one featured player to play — the Home visibility gate.
    var hasContent: Bool { !(pool?.players.isEmpty ?? true) }

    func isPlayed(_ player: KnowHerPlayer) -> Bool {
        guard let weekKey else { return false }
        return isPlayed(editionKey: player.editionKey(weekKey: weekKey))
    }

    func score(for player: KnowHerPlayer) -> Int? {
        guard let weekKey else { return nil }
        return score(editionKey: player.editionKey(weekKey: weekKey))
    }

    /// Raw edition-key lookups — the week-agnostic core the convenience `…(for:)` reads delegate to.
    /// Use these for a LAST-WEEK player, whose editionKey carries `previousWeekKey`, not the current one
    /// (the `…(for:)` variants assume the current week and would read the wrong edition).
    func isPlayed(editionKey: String) -> Bool { scores[editionKey] != nil }
    func score(editionKey: String) -> Int? { scores[editionKey] }

    // MARK: Last week (the picker's grace-window section)

    /// Last week's featured players (empty when there's no retained prior week).
    var previousPlayers: [KnowHerPlayer] { previousPool?.players ?? [] }
    var previousWeekKey: String? { previousPool?.weekKey }
    var hasPreviousWeek: Bool { !(previousPool?.players.isEmpty ?? true) }

    /// Players not yet completed this week — drives the "N of M played" card line + the
    /// picker's "Next player" flow.
    var unplayedPlayers: [KnowHerPlayer] { players.filter { !isPlayed($0) } }
    var playedCount: Int { players.filter { isPlayed($0) }.count }
    var allPlayed: Bool { hasContent && unplayedPlayers.isEmpty }

    /// Superfan contribution (docs §11): the sum of every banked edition score. Cumulative,
    /// points-like — comparable to Trivia's lifetime-correct in `GameCenterScores.superfanTotal`.
    var totalPoints: Int { scores.values.reduce(0, +) }

    // MARK: - Mutation

    /// Bank a completed edition and bump the weekly streak (§14). Idempotent per edition —
    /// re-recording a completed edition does nothing (no replay, no double-count).
    func recordCompletion(editionKey: String, weekKey: String, correct: Int) {
        guard scores[editionKey] == nil else { return }
        scores[editionKey] = correct

        // Weekly streak: continue if the last completed week was the immediately-prior week key,
        // else (re)start at 1. The first completion in a NEW week bumps it; later players the
        // same week don't (already stamped).
        if lastCompletedWeek != weekKey {
            if let last = lastCompletedWeek, Self.isConsecutiveWeek(previous: last, current: weekKey) {
                weeklyStreak += 1
            } else {
                weeklyStreak = 1
            }
            bestWeeklyStreak = max(bestWeeklyStreak, weeklyStreak)
            lastCompletedWeek = weekKey
        }
        persist()
    }

    // MARK: - Helpers

    /// Whether `current` is exactly one ISO-week after `previous` (keys like "2026-W27").
    /// Handles the year boundary loosely (any "…-W1"/"-W01" right after a late week counts);
    /// an unparseable pair just restarts the streak (safe).
    static func isConsecutiveWeek(previous: String, current: String) -> Bool {
        func parse(_ s: String) -> (Int, Int)? {
            let parts = s.split(separator: "-")
            guard parts.count >= 2, let year = Int(parts[0]) else { return nil }
            let wk = parts[1].uppercased().replacingOccurrences(of: "W", with: "")
            guard let week = Int(wk) else { return nil }
            return (year, week)
        }
        guard let (py, pw) = parse(previous), let (cy, cw) = parse(current) else { return false }
        if cy == py { return cw == pw + 1 }
        if cy == py + 1 { return cw <= 1 && pw >= 52 } // wrapped past year end
        return false
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(scores), forKey: Key.scores)
        defaults.set(weeklyStreak, forKey: Key.weeklyStreak)
        defaults.set(bestWeeklyStreak, forKey: Key.bestWeeklyStreak)
        defaults.set(lastCompletedWeek, forKey: Key.lastCompletedWeek)
    }

    /// Wipe local Know Her progress on account deletion (mirrors TriviaStore). The server
    /// `quiz_answers` rows are removed by the account-delete cascade; this clears the cache.
    func resetForAccountDeletion() {
        scores = [:]
        weeklyStreak = 0
        bestWeeklyStreak = 0
        lastCompletedWeek = nil
        previousPool = nil
        defaults.removeObject(forKey: Key.previousPool)
        persist()
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    #if DEBUG
    /// Dev-only wipe so `-resetOnboarding` simulates a fresh install (see NWSLAppApp.init).
    /// Writes cleared sentinels rather than `removeObject` (cfprefsd snapshot gotcha — see
    /// TriviaStore.debugResetState).
    static func debugResetState(defaults: UserDefaults = .standard) {
        defaults.set(Data(), forKey: Key.scores)
        defaults.set(0, forKey: Key.weeklyStreak)
        defaults.set(0, forKey: Key.bestWeeklyStreak)
        defaults.set("", forKey: Key.lastCompletedWeek)
        defaults.set(Data(), forKey: Key.previousPool)
    }
    #endif
}
