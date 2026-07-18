//
//  LeaderboardRanking.swift
//  NWSLApp
//
//  Shared "top-N + your rank" rule for every Fan Zone leaderboard (Predict the XI,
//  Bracket Battle). WHY it exists: the boards used to fetch the WHOLE scored set to
//  draw a short list — fine at launch, but a global board (Bracket, league-wide) is
//  one row per player, so at 100k users a single open pulled ~100k rows (megabytes of
//  egress) just to render a top list. The fix is standard leaderboard practice: fetch
//  only the top `visibleLimit`, and show the signed-in user their OWN true position —
//  computed with a cheap COUNT ("how many players outscore me?"), never by downloading
//  everyone. This file holds the one piece of logic all boards share: given the user's
//  true rank, decide WHERE their row goes.
//
//  Honesty (NO SILENT FAILURES): a bare `.limit(100)` would splice a #412 player in at
//  rank ~101 — a flattering LIE. `placement` returns `.belowFold(trueRank)` so the UI
//  shows "#412 · You" under a divider instead. Signed-out → `.none` (no You row).
//

import Foundation

enum LeaderboardRanking {
    /// How many rows a capped board fetches + shows. The signed-in user is always shown
    /// their real standing on top of this, however far down they are.
    static let visibleLimit = 100

    /// Where the signed-in user's own row belongs in a board capped to `visibleLimit`.
    enum YouPlacement: Equatable {
        case none            // signed out — no "You" row at all
        case inline(Int)     // user is within the window: insert their row at this 0-based slot
        case belowFold(Int)  // user ranks past the window: show a separated "You" row at this true rank
    }

    /// Decide the placement from the user's TRUE rank (1-based, `nil` when signed out)
    /// and the number of rival rows actually fetched (already capped at `visibleLimit`).
    ///
    /// - `nil` rank → `.none`.
    /// - rank ≤ `visibleLimit` → `.inline`, clamped so the slot never runs past the rivals
    ///   we have (a board smaller than the cap still places the user correctly).
    /// - rank > `visibleLimit` → `.belowFold` carrying the real rank for the splice row.
    static func placement(trueRank: Int?, cappedRivalCount: Int) -> YouPlacement {
        guard let rank = trueRank else { return .none }
        guard rank <= visibleLimit else { return .belowFold(rank) }
        return .inline(min(rank - 1, cappedRivalCount))
    }
}
