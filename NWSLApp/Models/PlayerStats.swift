//
//  PlayerStats.swift
//  NWSLApp
//
//  Season stat lines for the Teams pages: a per-player block on PlayerDetailView
//  and the team-leaders board on TeamDetailView's Stats sub-tab.
//
//  These are populated by ⚠️StatsProvider, a TEMP deterministic simulation (the
//  per-player stat *numbers* aren't a real feed — ESPN's per-athlete stats are
//  sparse and there's no lineup endpoint). They're position-aware and stable per
//  player, in the same spirit as the Bracket "community" simulation. The shapes
//  here are what a real stats endpoint would return, so the views don't change
//  when one lands.
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

    var id: String { athleteID }
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
