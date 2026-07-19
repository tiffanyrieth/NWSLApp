//
//  AthleteStatistics.swift
//  NWSLApp
//
//  Decode layer for ESPN's "Core" API per-athlete season statistics:
//    https://sports.core.api.espn.com/v2/sports/soccer/leagues/usa.nwsl/
//      seasons/{year}/types/1/athletes/{id}/statistics
//  (types/1 = Regular Season. The no-season variant returns CAREER totals, so we
//  always go through the season-scoped path — see ESPNService.seasonStats.)
//
//  Same defensive, two-layer approach as Roster.swift / MatchSummary.swift: the
//  decode wrappers mirror ESPN's nesting with everything optional (it's an
//  unofficial API and can change shape), and a mapper flattens them into the
//  view-facing `PlayerSeasonStats` (Models/PlayerStats.swift). A player who hasn't
//  featured returns sparse/empty categories, so a missing stat maps to 0 rather
//  than failing.
//
//  Payload shape (trimmed to what we use):
//    { "splits": { "categories": [
//        { "name": "general",  "stats": [ { "name": "appearances", "value": 11 }, … ] },
//        { "name": "offensive","stats": [ { "name": "totalGoals",  "value": 1  }, … ] },
//        …
//    ] } }
//

import Foundation

struct AthleteStatistics: Decodable {
    let splits: Splits?

    struct Splits: Decodable {
        let categories: [Category]?
    }

    struct Category: Decodable {
        let name: String?
        let stats: [Stat]?
    }

    struct Stat: Decodable {
        let name: String?
        let value: Double?          // ESPN sends the numeric value as a Double
        let displayValue: String?   // e.g. "11" — unused for now, kept for parity
    }
}

extension AthleteStatistics {
    /// Flatten the nested categories into `"category.statName" → value`, e.g.
    /// `["general.appearances": 11, "offensive.totalGoals": 1, …]`. Entries with a
    /// missing category- or stat-name are skipped.
    func flattened() -> [String: Double] {
        var out: [String: Double] = [:]
        for category in splits?.categories ?? [] {
            guard let categoryName = category.name else { continue }
            for stat in category.stats ?? [] {
                guard let statName = stat.name, let value = stat.value else { continue }
                out["\(categoryName).\(statName)"] = value
            }
        }
        return out
    }

    /// Map to the view-facing season line. `isGoalkeeper` is supplied by the caller
    /// from the roster position — NOT inferred from which stat categories are
    /// present (ESPN includes a `goalKeeping` category for outfielders too). A
    /// missing stat resolves to 0; Doubles round to the nearest Int.
    func playerSeasonStats(athleteID: String, isGoalkeeper: Bool) -> PlayerSeasonStats {
        let f = flattened()
        func int(_ key: String) -> Int { Int((f[key] ?? 0).rounded()) }

        return PlayerSeasonStats(
            athleteID: athleteID,
            appearances: int("general.appearances"),
            minutes: int("general.minutes"),
            goals: int("offensive.totalGoals"),
            assists: int("offensive.goalAssists"),
            shots: int("offensive.totalShots"),
            saves: int("goalKeeping.saves"),
            cleanSheets: int("goalKeeping.cleanSheet"),
            goalsAgainst: int("goalKeeping.goalsConceded"),
            isGoalkeeper: isGoalkeeper,
            all: f                       // full stat set → the grouped detail sections
        )
    }
}
