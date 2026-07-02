//
//  FanZoneSeenStore.swift
//  NWSLApp
//
//  The Fan Zone "have you seen this yet?" state (docs/know-her-game.md §10) — the persistence
//  behind the unified 3-state per-card model (new/unseen · seen/in-progress · done). Shared app
//  state injected app-wide via `.environment` in RootTabView, like the game stores.
//
//  Each game has a CYCLE KEY that identifies its current content window (Trivia = the day,
//  Bracket = the round, Predict = the open fixture, Know Her = the week). When the current cycle
//  key differs from the last one the user OPENED for that game, the card is "unseen" and shows a
//  dot; opening the game stamps the current cycle as seen and the dot clears. A new cycle (new
//  day/round/fixture/week) changes the key, so the dot returns — this is what makes the Fan Zone
//  feel alive ("would I open it today if I opened it yesterday?"). Tiny + durable: one string per
//  game in UserDefaults.
//

import Foundation

@Observable
final class FanZoneSeenStore {
    /// game key ("predict"/"bracket"/"trivia"/"knowher") → the cycle key the user last opened.
    private(set) var seen: [String: String]

    private let defaults: UserDefaults
    private static let key = "fanzone.seen.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.seen = (defaults.dictionary(forKey: Self.key) as? [String: String]) ?? [:]
    }

    /// True when `game` has fresh content the user hasn't opened yet: there IS a current cycle,
    /// it isn't already done, and the user's last-seen cycle for this game differs. `cycleKey`
    /// nil (no active content) → never unseen.
    func isUnseen(game: String, cycleKey: String?, isDone: Bool) -> Bool {
        guard let cycleKey, !isDone else { return false }
        return seen[game] != cycleKey
    }

    /// Stamp `game`'s current cycle as opened — clears the dot until the next cycle. No-op when
    /// there's no active cycle. Idempotent.
    func markSeen(game: String, cycleKey: String?) {
        guard let cycleKey, seen[game] != cycleKey else { return }
        seen[game] = cycleKey
        defaults.set(seen, forKey: Self.key)
    }

    #if DEBUG
    /// Dev-only wipe so `-resetOnboarding` simulates a fresh install (every card reads as new).
    static func debugResetState(defaults: UserDefaults = .standard) {
        defaults.set([String: String](), forKey: key)
    }
    #endif
}
