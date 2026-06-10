//
//  AthleteStatsCache.swift
//  NWSLApp
//
//  A tiny in-memory cache for per-athlete season stats, keyed by athlete id + year.
//  Player season stats change slowly (once per match a player features in), but a
//  team page is re-opened often and fans out ~25 Core-API calls each time — so we
//  cache the mapped result for the app session to avoid refetching and to keep the
//  unofficial host from being hammered (see ESPNService.seasonStats).
//
//  An `actor` gives us concurrency-safe access for free: the parallel task group
//  in ESPNService reads/writes this from many tasks at once. Every result is stored
//  — including an all-zero line for a player who hasn't featured — so a no-stats
//  player isn't refetched on every reopen. It's session-scoped (not persisted);
//  the app already refetches the roster on each visit.
//

import Foundation

actor AthleteStatsCache {
    private var byKey: [String: PlayerSeasonStats] = [:]

    private func key(_ athleteID: String, _ year: Int) -> String { "\(athleteID)-\(year)" }

    func cached(athleteID: String, year: Int) -> PlayerSeasonStats? {
        byKey[key(athleteID, year)]
    }

    func store(_ stats: PlayerSeasonStats, year: Int) {
        byKey[key(stats.athleteID, year)] = stats
    }
}
