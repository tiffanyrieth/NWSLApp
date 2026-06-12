//
//  PredictionMatchProvider.swift
//  NWSLApp
//
//  ⚠️ TEMP / SCAFFOLDING — the simulated Predict the XI leaderboard only.
//
//  The match slate is now LIVE (0.3.9): PredictXIViewModel builds real fixtures
//  from the shared MatchStore + the user's follows, and scores submitted
//  predictions against ESPN `/summary`. What remains seeded is the *leaderboard* —
//  fixed sample usernames the solo player is ranked among — because a real
//  multi-user board needs a server.
//
//  WHEN REMOVED: replace `leaderboardOpponents()` with a real per-team board once
//  multi-user scoring exists. That's the separate **Game Center** backbone item
//  (GameKit leaderboards across all three Fan Zone games) — not this PR.
//

import Foundation

struct PredictionMatchProvider {
    /// Sample opponents for the simulated leaderboard — fixed season-point totals
    /// the user (whose points grow as settled predictions score) is ranked among.
    func leaderboardOpponents() -> [(name: String, points: Int)] { Self.opponents }

    // Soccer-fan-flavoured handles + fixed totals spanning a believable range, so
    // the user climbs the board as settled matches score.
    private static let opponents: [(name: String, points: Int)] = [
        ("xiwhisperer", 64),
        ("lineup_lucy", 53),
        ("formationfanatic", 47),
        ("captain_calls", 41),
        ("gk_guru", 35),
        ("firstgoalfran", 28),
        ("subzero_sub", 22),
        ("benchmob", 17),
        ("predict_pat", 12),
        ("coinflip_kim", 7),
        ("rookie_riley", 3),
    ]
}
