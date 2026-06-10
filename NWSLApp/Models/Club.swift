//
//  Club.swift
//  NWSLApp
//
//  The league's club directory, decoded from ESPN's unofficial NWSL teams
//  endpoint:
//    https://site.api.espn.com/apis/site/v2/sports/soccer/usa.nwsl/teams
//
//  Named `Club` (not `Team`) on purpose: the scoreboard already has a `Team`
//  type for a competitor's club-within-a-match (see Scoreboard.swift). This is
//  a different context — the league-wide directory — so it gets its own,
//  flat, view-friendly model. "Club" is also the correct soccer term.
//

import Foundation

/// A league club, flattened from ESPN's deeply nested teams payload so views
/// and the FollowingStore can use a simple, stable shape.
struct Club: Identifiable, Hashable {
    let id: String
    let displayName: String
    let abbreviation: String
    let logoURL: String?
    /// ESPN's short form ("Angel City", "Washington", "Kansas City") — the
    /// chip-friendly label for the Feed tab's per-team filters, where the full
    /// `displayName` ("Kansas City Current") would be too long. Defaulted so
    /// existing call sites that don't set it fall back to `displayName`.
    var shortName: String? = nil
    /// ESPN's primary/alternate brand hex (6 digits, no "#"). Drives the team-
    /// color ring crests and accents across the app's ClubStore readers (match
    /// cards, standings, teams, coming-up). Defaulted so older call sites that
    /// build a Club by hand still compile. Resolve via `brandHex`/`ringColor`
    /// below, which apply the TeamBrandColors override first.
    var color: String? = nil
    var alternateColor: String? = nil
}

// MARK: - ESPN teams endpoint decoding
//
// Payload shape (trimmed to what we use):
//   { "sports": [ { "leagues": [ { "teams": [ { "team": {
//       "id": "15365", "abbreviation": "WAS",
//       "displayName": "Washington Spirit", "isActive": true,
//       "logos": [ { "href": "https://.../15365.png" } ]
//   } } ] } ] } ] }
//
// The wrapper structs below mirror that nesting only far enough to reach the
// team objects. Everything is optional because ESPN is unofficial and can
// change shape without warning — a missing field should degrade, not crash.

struct TeamsResponse: Decodable {
    let sports: [Sport]?

    /// Flatten the nested payload into active clubs, sorted alphabetically.
    var clubs: [Club] {
        let wrappers = sports?.first?.leagues?.first?.teams ?? []
        return wrappers
            .compactMap { wrapper -> Club? in
                guard let team = wrapper.team,
                      team.isActive ?? true,
                      let id = team.id else { return nil }
                return Club(
                    id: id,
                    displayName: team.displayName ?? team.shortDisplayName ?? team.abbreviation ?? "—",
                    abbreviation: team.abbreviation ?? "",
                    logoURL: team.logos?.first?.href,
                    shortName: team.shortDisplayName,
                    color: team.color,
                    alternateColor: team.alternateColor
                )
            }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    struct Sport: Decodable { let leagues: [League]? }
    struct League: Decodable { let teams: [TeamWrapper]? }
    struct TeamWrapper: Decodable { let team: RawTeam? }

    struct RawTeam: Decodable {
        let id: String?
        let abbreviation: String?
        let displayName: String?
        let shortDisplayName: String?
        let isActive: Bool?
        let logos: [Logo]?
        // ESPN's brand colors, present on the /teams payload (6-hex, no "#").
        let color: String?
        let alternateColor: String?
    }

    struct Logo: Decodable { let href: String? }
}
