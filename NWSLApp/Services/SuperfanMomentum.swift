//
//  SuperfanMomentum.swift
//  NWSLApp
//
//  The FORGIVING engagement "momentum" that fills each Superfan channel's 5 engagement points (economy
//  rebuild 2026-08-05). Owner law: reward showing up, keep the score honest all season, never punish a
//  single miss ([[feedback_superfan_points_philosophy]]).
//
//  The model: momentum (0–5) per game. +1 each cycle you PLAY; −1 for each cycle you MISS; floored at 0,
//  capped at 5. Recovers the moment you come back — a busy week costs ONE point, not a wipeout, and it's
//  never a reset. Crucially it DECAYS if you stop, so engagement is never a permanent free 5 you set and
//  forget — you have to keep turning up to keep it (the anti-"handed-out-points" property).
//
//  Cheap + universal clock: absolute WEEK ordinals (weeks since the epoch), and a per-game CADENCE in
//  weeks — Predict/Bracket play ~weekly (cadence 1), KHG/Trivia are biweekly rounds (cadence 2) — so one
//  "missed cycle" means a missed KHG round (2 weeks), not a bare week. Decay is computed on READ from the
//  stored (momentum, lastWeek); no history is kept. Season-scoped so a new season starts fresh.
//
//  ⚠️ Offseason NOTE (v1, tunable): a game that's out of season still decays because we don't yet gate on
//  availability — but the tier-floor lock + the frozen accuracy hold the SCORE up, so at worst the ≤5
//  engagement points fade over a long break and rebuild on return. Freeze-when-out-of-season is a later refinement.
//

import Foundation

/// Pure momentum math — no I/O, unit-tested. `SuperfanMomentumStore` owns persistence.
enum SuperfanMomentum {
    /// How many weeks make one "cycle" of each game (its cadence). A missed cycle = one lost point.
    static let cadenceWeeks: [SuperfanGame: Int] = [.predict: 1, .bracket: 1, .khg: 2, .trivia: 2]
    static var cap: Int { SuperfanScoring.engagementMax }   // 5

    struct State: Codable, Equatable { var momentum: Int; var lastWeek: Int }

    /// Absolute week ordinal — a universal, always-available clock (no season/offseason gaps).
    static func currentWeek(now: Date) -> Int { Int(now.timeIntervalSince1970 / (7 * 86_400)) }

    /// The decayed momentum given the stored state and the current week. nil state (never played) ⇒ 0.
    /// The CURRENT cycle isn't counted as missed (you could still play it), so a just-opened cycle doesn't
    /// dock you before you've had the chance.
    static func effective(state: State?, game: SuperfanGame, currentWeek: Int) -> Int {
        guard let s = state else { return 0 }
        let cadence = max(1, cadenceWeeks[game] ?? 1)
        let cyclesSince = max(0, currentWeek - s.lastWeek) / cadence
        let missed = max(0, cyclesSince - 1)
        return min(cap, max(0, s.momentum - missed))
    }

    /// The new state after playing a cycle now: decay to the present, then +1.
    static func afterPlay(state: State?, game: SuperfanGame, currentWeek: Int) -> State {
        State(momentum: min(cap, effective(state: state, game: game, currentWeek: currentWeek) + 1),
              lastWeek: currentWeek)
    }
}

/// Per-game, per-season local persistence of the momentum state. The game finish/submit hooks call
/// `recordPlay`; the store→counts bridge reads `effective`.
enum SuperfanMomentumStore {
    private static func key(_ game: SuperfanGame, _ season: Int) -> String {
        "superfan.momentum.\(season).\(game.rawValue)"
    }

    static func state(_ game: SuperfanGame, season: Int, defaults: UserDefaults = .standard) -> SuperfanMomentum.State? {
        guard let data = defaults.data(forKey: key(game, season)) else { return nil }
        return try? JSONDecoder().decode(SuperfanMomentum.State.self, from: data)
    }

    /// Record a play of `game` — bumps its momentum (after decaying to now). Called at the PLAY/submit
    /// action (not scoring), since momentum measures showing up.
    static func recordPlay(_ game: SuperfanGame, season: Int, now: Date = Date(), defaults: UserDefaults = .standard) {
        let week = SuperfanMomentum.currentWeek(now: now)
        let new = SuperfanMomentum.afterPlay(state: state(game, season: season, defaults: defaults),
                                             game: game, currentWeek: week)
        if let data = try? JSONEncoder().encode(new) { defaults.set(data, forKey: key(game, season)) }
    }

    /// The current decayed momentum (0–5) for the bridge.
    static func effective(_ game: SuperfanGame, season: Int, now: Date = Date(), defaults: UserDefaults = .standard) -> Int {
        SuperfanMomentum.effective(state: state(game, season: season, defaults: defaults),
                                   game: game, currentWeek: SuperfanMomentum.currentWeek(now: now))
    }
}
