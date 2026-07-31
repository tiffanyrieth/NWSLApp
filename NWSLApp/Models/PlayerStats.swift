//
//  PlayerStats.swift
//  NWSLApp
//
//  Season stat lines for the Teams pages: a per-player block on PlayerDetailView
//  and the team-leaders board on TeamDetailView's Stats sub-tab.
//
//  These are populated from real ESPN Core API per-athlete season totals
//  (ESPNService.seasonStats, decoded via AthleteStatistics.swift). This file is the
//  view-facing domain layer — the ESPN-shaped decode wrappers live separately.
//

import Foundation

/// One player's season totals. Outfield players use goals/assists/shots; keepers
/// use saves/cleanSheets/goalsAgainst. `isGoalkeeper` drives which set a view shows.
struct PlayerSeasonStats: Identifiable, Hashable {
    let athleteID: String

    let appearances: Int
    let minutes: Int

    // Outfield
    let goals: Int
    let assists: Int
    let shots: Int

    // Goalkeeper
    let saves: Int
    let cleanSheets: Int
    let goalsAgainst: Int

    let isGoalkeeper: Bool

    /// The FULL flattened stat set (`"category.statName" → value`) from ESPN's ~100-stat
    /// response, so the player screen can show grouped detail sections beyond the headline
    /// line. Empty for stats built without it (previews, the summary path). See seasonSections.
    var all: [String: Double] = [:]

    var id: String { athleteID }
}

// MARK: - Grouped season sections (the expanded player-stats screen)

struct SeasonStatSection: Identifiable {
    let title: String
    let items: [SeasonStatItem]
    var id: String { title }
}

struct SeasonStatItem: Identifiable {
    let label: String
    let value: String
    var id: String { label }
}

extension PlayerSeasonStats {
    /// Grouped, position-aware season stat sections built from the full `all` dict, showing
    /// ONLY non-zero stats (no wall of zeros) and dropping any section that ends up empty.
    /// Empty when `all` wasn't populated — the view falls back to the headline line.
    var seasonSections: [SeasonStatSection] {
        func count(_ key: String, _ label: String) -> SeasonStatItem? {
            guard let v = all[key], v != 0 else { return nil }
            return SeasonStatItem(label: label, value: "\(Int(v.rounded()))")
        }
        // ESPN sends rates as 0–1 fractions ("0.7" = 70%); guard both shapes.
        func pct(_ key: String, _ label: String) -> SeasonStatItem? {
            guard let v = all[key], v > 0 else { return nil }
            return SeasonStatItem(label: label, value: "\(Int((v <= 1 ? v * 100 : v).rounded()))%")
        }
        // ⚠️ DO NOT render ESPN's `goalKeeping.savePct` — it is NOT a save percentage.
        // It is literally saves ÷ 100 (verified live 2026-07-31 in BOTH leagues: Lorena
        // 36 saves / 17 conceded → ESPN `.360` where the true rate is 68%; Nali 3 saves /
        // 0 conceded → ESPN `.030` where the true rate is 100%). The tell is the display
        // format: ESPN prints it batting-average style (".360") while every genuine rate
        // in the same payload comes back as "0.7". Showing it produced a plausible-looking
        // wrong number on every keeper page, which is the banned failure-that-looks-like-
        // success — so we compute the rate from two fields ESPN does get right.
        func saveRate() -> SeasonStatItem? {
            let saves = all["goalKeeping.saves"] ?? 0
            let conceded = all["goalKeeping.goalsConceded"] ?? 0
            let faced = saves + conceded
            guard faced > 0 else { return nil } // no shots faced ⇒ no rate, not "0%"
            return SeasonStatItem(label: "Save %", value: "\(Int((saves / faced * 100).rounded()))%")
        }
        func section(_ title: String, _ items: [SeasonStatItem?]) -> SeasonStatSection? {
            let real = items.compactMap { $0 }
            return real.isEmpty ? nil : SeasonStatSection(title: title, items: real)
        }

        var out: [SeasonStatSection?] = [
            section("Overview", [
                count("general.appearances", "Appearances"),
                count("general.starts", "Starts"),
                count("general.minutes", "Minutes"),
            ]),
        ]
        if isGoalkeeper {
            out += [
                section("Goalkeeping", [
                    count("goalKeeping.saves", "Saves"),
                    saveRate(), // computed — see saveRate(); ESPN's savePct is saves÷100
                    count("goalKeeping.cleanSheet", "Clean sheets"),
                    count("goalKeeping.goalsConceded", "Goals conceded"),
                    count("goalKeeping.penaltyKicksSaved", "Penalties saved"),
                    count("goalKeeping.punches", "Punches"),
                    count("goalKeeping.crossesCaught", "Crosses caught"),
                    count("goalKeeping.bigChanceSaves", "Big-chance saves"),
                ]),
                section("Distribution", [
                    pct("general.passPct", "Pass %"),
                    count("offensive.accuratePasses", "Accurate passes"),
                    count("offensive.totalLongBalls", "Long balls"),
                    count("general.touches", "Touches"),
                ]),
            ]
        } else {
            out += [
                section("Attacking", [
                    count("offensive.totalGoals", "Goals"),
                    count("offensive.goalAssists", "Assists"),
                    count("offensive.totalShots", "Shots"),
                    count("offensive.shotsOnTarget", "On target"),
                    count("offensive.shotAssists", "Key passes"),
                    count("offensive.bigChanceCreated", "Big chances"),
                ]),
                section("Passing", [
                    pct("general.passPct", "Pass %"),
                    count("offensive.accuratePasses", "Accurate passes"),
                    count("offensive.totalCrosses", "Crosses"),
                    count("offensive.totalLongBalls", "Long balls"),
                    count("general.touches", "Touches"),
                    count("offensive.progressiveCarries", "Progressive carries"),
                ]),
                section("Defending", [
                    count("defensive.totalTackles", "Tackles"),
                    count("defensive.interceptions", "Interceptions"),
                    count("defensive.totalClearance", "Clearances"),
                    count("defensive.recoveries", "Recoveries"),
                    count("general.duelsWon", "Duels won"),
                    count("defensive.blockedShots", "Blocks"),
                ]),
            ]
        }
        out.append(section("Discipline", [
            count("general.foulsCommitted", "Fouls"),
            count("general.foulsSuffered", "Fouls won"),
            count("general.yellowCards", "Yellow cards"),
            count("general.redCards", "Red cards"),
            count("offensive.offsides", "Offsides"),
        ]))
        return out.compactMap { $0 }
    }
}

/// One row of a team-leaders list: a player and their value in some category.
struct StatLeader: Identifiable, Hashable {
    let athleteID: String
    let name: String        // short display name, e.g. "T. Rodman"
    let value: Int
    var id: String { athleteID }
}

/// The team's stat leaders — top players in each category, already ranked. Built
/// in TeamDetailViewModel from the same per-player stats the player pages show, so
/// the leaderboard and each player's page always agree.
struct TeamLeaders {
    let topScorers: [StatLeader]
    let topAssists: [StatLeader]
    let topCleanSheets: [StatLeader]

    var isEmpty: Bool {
        topScorers.isEmpty && topAssists.isEmpty && topCleanSheets.isEmpty
    }
}
