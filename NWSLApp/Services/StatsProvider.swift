//
//  StatsProvider.swift
//  NWSLApp
//
//  ⚠️ TEMP / SCAFFOLDING — a deterministic stand-in for a real player-stats feed.
//
//  WHAT: given a club's roster, returns a PlayerSeasonStats line for every player
//  so the Teams pages (PlayerDetailView's season block + TeamDetailView's
//  team-leaders board) show real, consistent content instead of a "coming soon"
//  card.
//
//  WHY: ESPN's unofficial endpoints expose only sparse, inconsistent per-athlete
//  stats (and no lineup/formation feed), so hand-curating 16 full squads isn't
//  practical. Instead the numbers are *simulated* — deterministically, so they're
//  stable per player on every launch and internally consistent (the leaderboard
//  is derived from these exact lines). This mirrors the Bracket Battle "community"
//  simulation: clearly demo data, not a real source.
//
//  The numbers are position-aware (forwards score, keepers keep clean sheets) and
//  seed-weighted by a small marquee list so recognizable names tend to top their
//  team — the same seed-weighting idea the Bracket sim uses for favourites.
//
//  WHEN REMOVED: replace `seasonStats(for:)` with a real per-team stats endpoint
//  returning the same `[PlayerSeasonStats]`. The async signature is already shaped
//  for it; TeamDetailViewModel and the views don't change.
//

import Foundation

struct StatsProvider {
    /// One stat line per athlete, keyed by athlete id. Async so a real networked
    /// source can drop in behind the same call.
    func seasonStats(for athletes: [Athlete]) async -> [PlayerSeasonStats] {
        athletes.map { Self.generate(for: $0) }
    }

    // MARK: - Deterministic generation

    private static func generate(for athlete: Athlete) -> PlayerSeasonStats {
        var gen = SeededGenerator(seed: stableHash(athlete.id))

        // A roughly-realistic NWSL season is ~26 games; sample appearances and
        // derive minutes from a per-appearance average so the two stay coherent.
        let apps = Int.random(in: 6...24, using: &gen)
        let minutes = Int(Double(apps) * Double.random(in: 45...89, using: &gen))
        let marquee = marqueeNames.contains(athlete.name)

        switch position(of: athlete) {
        case .goalkeeper:
            // Keep the keeper line internally coherent: goals-against runs roughly
            // per-game, clean sheets are a believable fraction of apps (so a low GA
            // and zero clean sheets can't disagree), and saves scale with games.
            let goalsAgainst = Int((Double(apps) * Double.random(in: 0.7...1.7, using: &gen)).rounded())
            let cleanSheets = min(apps, Int((Double(apps) * Double.random(in: 0.10...0.45, using: &gen)).rounded()))
            let saves = apps * Int.random(in: 2...4, using: &gen) + Int.random(in: 0...10, using: &gen)
            return PlayerSeasonStats(
                athleteID: athlete.id, appearances: apps, minutes: minutes,
                goals: 0, assists: 0, shots: 0,
                saves: saves, cleanSheets: cleanSheets, goalsAgainst: goalsAgainst,
                isGoalkeeper: true
            )

        case .forward:
            let goals = count(max: 14, apps: apps, boost: marquee ? 1.5 : 0.9, gen: &gen)
            let assists = count(max: 8, apps: apps, boost: marquee ? 1.1 : 0.8, gen: &gen)
            let shots = goals * Int.random(in: 3...5, using: &gen) + Int.random(in: 4...18, using: &gen)
            return outfield(athlete, apps, minutes, goals, assists, shots)

        case .midfielder:
            let goals = count(max: 7, apps: apps, boost: marquee ? 1.1 : 0.7, gen: &gen)
            let assists = count(max: 9, apps: apps, boost: marquee ? 1.3 : 1.0, gen: &gen)
            let shots = goals * Int.random(in: 2...4, using: &gen) + Int.random(in: 3...14, using: &gen)
            return outfield(athlete, apps, minutes, goals, assists, shots)

        case .defender:
            let goals = count(max: 3, apps: apps, boost: 0.6, gen: &gen)
            let assists = count(max: 4, apps: apps, boost: 0.7, gen: &gen)
            let shots = goals * Int.random(in: 2...4, using: &gen) + Int.random(in: 1...8, using: &gen)
            return outfield(athlete, apps, minutes, goals, assists, shots)
        }
    }

    /// Assemble an outfield line (no keeper fields).
    private static func outfield(
        _ athlete: Athlete, _ apps: Int, _ minutes: Int,
        _ goals: Int, _ assists: Int, _ shots: Int
    ) -> PlayerSeasonStats {
        PlayerSeasonStats(
            athleteID: athlete.id, appearances: apps, minutes: minutes,
            goals: goals, assists: assists, shots: shots,
            saves: 0, cleanSheets: 0, goalsAgainst: 0,
            isGoalkeeper: false
        )
    }

    /// A non-negative count biased toward fuller seasons and an optional boost,
    /// clamped to `max`. `max <= 0` returns 0 (e.g. a keeper's outfield fields).
    private static func count(max: Int, apps: Int, boost: Double, gen: inout SeededGenerator) -> Int {
        guard max > 0 else { return 0 }
        let raw = Double.random(in: 0...Double(max), using: &gen)
        let scaled = raw * (Double(apps) / 24.0) * boost
        return min(max, Int(scaled.rounded()))
    }

    private enum Position { case goalkeeper, defender, midfielder, forward }

    /// Map ESPN's position to our four buckets; default to forward so an unknown
    /// position still gets attacking-shaped numbers rather than a blank line.
    private static func position(of athlete: Athlete) -> Position {
        switch athlete.positionAbbreviation?.uppercased() {
        case "G": return .goalkeeper
        case "D": return .defender
        case "M": return .midfielder
        case "F": return .forward
        default:
            switch athlete.positionName?.lowercased() {
            case let name? where name.contains("goal"): return .goalkeeper
            case let name? where name.contains("defend"): return .defender
            case let name? where name.contains("mid"): return .midfielder
            default: return .forward
            }
        }
    }

    /// A small set of recognizable NWSL names that get a scoring/assist boost so
    /// the simulated leaderboards surface familiar players. Matched by full name;
    /// a name not on any roster simply has no effect. Durable 2026 snapshot.
    private static let marqueeNames: Set<String> = [
        "Trinity Rodman", "Temwa Chawinga", "Barbra Banda", "Sophia Wilson",
        "Mallory Swanson", "Esther González", "Marta", "Debinha",
        "Racheal Kundananji", "Sveindís Jónsdóttir", "Ashley Hatch", "Lynn Williams",
        "Jaedyn Shaw", "Croix Bethune", "Ella Stevens", "Yazmeen Ryan",
    ]
}

// MARK: - Deterministic helpers
//
// Same FNV-1a hash + SplitMix64 generator the Bracket/Trivia sims use: a stable
// seed in, the same sequence out, on every launch (Swift's built-in Hasher is
// randomised per-process and would reshuffle stats between runs).

private func stableHash(_ string: String) -> UInt64 {
    var hash: UInt64 = 1_469_598_103_934_665_603
    for byte in string.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 1_099_511_628_211
    }
    return hash
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
