//
//  Standings.swift
//  NWSLApp
//
//  The league table, decoded from ESPN's unofficial NWSL standings endpoint:
//    https://site.api.espn.com/apis/v2/sports/soccer/usa.nwsl/standings
//
//  Note the path: standings lives under `apis/v2/…`, NOT the `apis/site/v2/…`
//  base the rest of the app uses (the `site/v2` standings path returns an empty
//  object). ESPNService builds this one URL explicitly for that reason.
//
//  Like Club.swift, this flattens ESPN's deeply nested payload into a simple,
//  view-friendly row. Each row carries a full `Club` (not just a name) so a
//  standings row can navigate straight into TeamDetailView and light up the
//  same Following lens as the Teams tab — the standings team `id` is the same
//  ESPN team id as `/teams` (verified: 15365 = Washington in both).
//

import Foundation

/// One team's line in the league table, flattened for the view. Holds a full
/// `Club` so the row is tappable (→ TeamDetailView) and follow-aware (the
/// FollowingStore keys on `Club.id`) with no extra lookup.
struct StandingsRow: Identifiable, Hashable {
    let rank: Int
    let club: Club
    let gamesPlayed: Int
    let wins: Int
    let draws: Int
    let losses: Int
    let points: Int

    var id: String { club.id }
}

// MARK: - ESPN standings endpoint decoding
//
// Payload shape (trimmed to what we use):
//   { "children": [ { "standings": { "entries": [ {
//       "team": { "id": "15365", "abbreviation": "WAS",
//                 "displayName": "Washington Spirit",
//                 "logos": [ { "href": "https://.../15365.png" } ] },
//       "stats": [ { "type": "wins", "value": 8.0 }, … ]
//   } ] } } ] }
//
// `children[0]` is the regular-season group. Each entry's `stats` is a flat
// array we look up by the stable `type` key (not display order, which can
// shift). Everything is optional because ESPN is unofficial and can change
// shape without warning — a missing field should degrade, not crash.

struct StandingsResponse: Decodable {
    let children: [Child]?

    /// Flatten the nested payload into table rows, sorted by rank (ascending).
    /// The feed already returns entries in rank order, but we sort defensively
    /// so the table is correct even if that ordering ever changes.
    var rows: [StandingsRow] {
        let entries = children?.first?.standings?.entries ?? []
        return entries.enumerated()
            .compactMap { index, entry in entry.row(fallbackRank: index + 1) }
            .sorted { $0.rank < $1.rank }
    }

    struct Child: Decodable { let standings: Standings? }
    struct Standings: Decodable { let entries: [Entry]? }

    struct Entry: Decodable {
        let team: RawTeam?
        let stats: [Stat]?

        /// Build a view row from this entry, or `nil` if it has no usable team.
        /// `fallbackRank` (1-based feed position) is used only if the `rank`
        /// stat is missing.
        func row(fallbackRank: Int) -> StandingsRow? {
            guard let team, let id = team.id else { return nil }

            let club = Club(
                id: id,
                displayName: team.displayName ?? team.shortDisplayName ?? team.abbreviation ?? "—",
                abbreviation: team.abbreviation ?? "",
                logoURL: team.logos?.first?.href
            )

            // Stats come back as Doubles ("8.0"); we present whole numbers.
            func stat(_ type: String) -> Int? {
                stats?.first { $0.type == type }.flatMap { $0.value }.map { Int($0) }
            }

            return StandingsRow(
                rank: stat("rank") ?? fallbackRank,
                club: club,
                gamesPlayed: stat("gamesplayed") ?? 0,
                wins: stat("wins") ?? 0,
                draws: stat("ties") ?? 0,        // ESPN calls draws "ties"
                losses: stat("losses") ?? 0,
                points: stat("points") ?? 0
            )
        }
    }

    struct RawTeam: Decodable {
        let id: String?
        let abbreviation: String?
        let displayName: String?
        let shortDisplayName: String?
        let logos: [Logo]?
    }

    struct Stat: Decodable {
        let type: String?
        let value: Double?
    }

    struct Logo: Decodable { let href: String? }
}
