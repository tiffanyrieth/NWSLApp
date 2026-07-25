//
//  SuperfanCountsCache.swift
//  NWSLApp
//
//  A tiny per-season UserDefaults mirror of the last SERVER-MERGED SuperfanCounts, so surfaces
//  that must stay network-free (the Home carousel's Superfan card, the Game Center submit) can
//  show the SAME score as the detail screen instead of a local-only undercount.
//
//  Why it exists (owner repro, 2026-07-25): after a reinstall, a user's history lives only in
//  `superfan_scores` — the detail screen server-merges and showed 46 while the Home card computed
//  from local stores alone and showed 25. Two numbers for one score is a trust bug.
//
//  Contract: WRITTEN only with counts that came back from `SuperfanService.submit` (already
//  GREATEST-merged with the server). READ as `local.merged(with: cached)` — the same monotonic
//  per-counter max the server merge uses, so local play between syncs still counts immediately
//  and the cache can never lower anything. Keyed per season; an app delete clears it (correct:
//  a fresh sign-in re-adopts from the server on the first detail sync).
//

import Foundation

enum SuperfanCountsCache {
    private static func key(season: Int) -> String { "superfan.mergedCounts.\(season)" }

    /// Persist counts that were just adopted from a server merge.
    static func save(_ counts: SuperfanCounts, season: Int, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(counts) {
            defaults.set(data, forKey: key(season: season))
        }
    }

    /// The last server-merged counts for `season` (`.zero` when never synced — merging with zero
    /// is the identity, so callers can merge unconditionally).
    static func load(season: Int, defaults: UserDefaults = .standard) -> SuperfanCounts {
        guard let data = defaults.data(forKey: key(season: season)),
              let counts = try? JSONDecoder().decode(SuperfanCounts.self, from: data)
        else { return .zero }
        return counts
    }
}
