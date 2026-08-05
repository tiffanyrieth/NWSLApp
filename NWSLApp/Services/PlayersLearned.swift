//
//  PlayersLearned.swift
//  NWSLApp
//
//  The "players you've learned" collection that anchors the rebuilt Superfan (2026-08-05, owner). Know Her
//  Game exists to teach you the roster, so a collection that GROWS as you play is the most on-brand thing
//  in the app — a reason to open Superfan (watch it fill) and a reason to play KHG (add to it).
//
//  Deliberately CHEAP: a bounded list (~10–30 players/season) of just the id, name, team and best score —
//  the same storage discipline as everything else (we keep small per-user facts, never deep history). Held
//  LOCALLY here (UserDefaults, per season); a durable server mirror can layer on later without changing
//  this read path (the owner confirmed local is fine for the collection). Deduped by athlete, keeping the
//  BEST score — replaying a player can only improve their stamp, never remove it.
//

import Foundation

/// One learned player — a stamp in the collection.
struct LearnedPlayer: Codable, Identifiable, Equatable {
    let athleteId: String
    let name: String
    let teamAbbr: String
    var bestCorrect: Int
    var outOf: Int
    let learnedAt: Double        // epoch seconds — for ordering (newest first)

    var id: String { athleteId }
}

/// Per-season local store of the collection. Pure w.r.t. an injectable `UserDefaults` so the merge/dedup
/// logic is unit-testable.
enum PlayersLearnedStore {
    private static func key(_ season: Int) -> String { "superfan.playersLearned.\(season)" }

    /// The collection, newest-learned first.
    static func load(season: Int, defaults: UserDefaults = .standard) -> [LearnedPlayer] {
        guard let data = defaults.data(forKey: key(season)),
              let list = try? JSONDecoder().decode([LearnedPlayer].self, from: data) else { return [] }
        return list.sorted { $0.learnedAt > $1.learnedAt }
    }

    /// Record (or improve) a player's stamp. Idempotent per athlete: a first play adds them; a replay only
    /// raises `bestCorrect` (keeping the earliest `learnedAt`), never lowers or removes.
    static func record(_ player: LearnedPlayer, season: Int, defaults: UserDefaults = .standard) {
        var list = load(season: season, defaults: defaults)
        if let i = list.firstIndex(where: { $0.athleteId == player.athleteId }) {
            if player.bestCorrect > list[i].bestCorrect {
                list[i].bestCorrect = player.bestCorrect
                list[i].outOf = player.outOf
            }
        } else {
            list.append(player)
        }
        if let data = try? JSONEncoder().encode(list) { defaults.set(data, forKey: key(season)) }
    }

    static func count(season: Int, defaults: UserDefaults = .standard) -> Int {
        load(season: season, defaults: defaults).count
    }
}
