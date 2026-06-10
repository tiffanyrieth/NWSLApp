//
//  Roster.swift
//  NWSLApp
//
//  A club's squad, decoded from ESPN's unofficial NWSL roster endpoint:
//    https://site.api.espn.com/apis/site/v2/sports/soccer/usa.nwsl/teams/{id}/roster
//
//  Same two-layer shape as Club.swift: defensive `RosterResponse` decode wrappers
//  that mirror ESPN's nesting, flattened into a simple, view-friendly `Athlete`.
//  Everything in the decode layer is optional because ESPN is unofficial and can
//  change shape without warning — a missing field should degrade, not crash.
//
//  Known NWSL data gap (verified against the live endpoint): player headshots are
//  null for every NWSL athlete, so we don't model or render a photo — the squad
//  cards (PlayerCard) show a jersey-number / initials monogram instead. This is a
//  deliberate, permanent decision for this league, not a TODO.
//
//  The same roster response also carries a lightweight team profile (color,
//  standing summary, record), surfaced here as `ClubSquad` so a single fetch
//  powers the whole Teams detail page — the colored cards AND the header line.
//

import Foundation

/// One player, flattened from ESPN's roster payload for the view layer.
struct Athlete: Identifiable, Hashable {
    let id: String
    let name: String               // full name, e.g. "Trinity Rodman"
    let shortName: String?         // ESPN's abbreviated form, e.g. "T. Rodman"
    let jersey: String?            // ESPN sends jersey as a String ("13"), like scores
    let positionName: String?      // "Goalkeeper", "Defender", …
    let positionAbbreviation: String?  // "G", "D", "M", "F"
    let age: Int?
    let displayHeight: String?     // e.g. "5' 10\""
    let citizenship: String?       // e.g. "USA"

    /// Whether this player is a goalkeeper, by position. Drives which season-stat
    /// set the player pages show (saves/clean-sheets vs. goals/assists). Position
    /// abbreviation is the reliable signal ("G"); the display name is a fallback
    /// for the rare case ESPN omits it.
    var isGoalkeeper: Bool {
        if positionAbbreviation?.uppercased() == "G" { return true }
        return positionName?.lowercased().contains("goal") ?? false
    }
}

/// The result of a roster fetch: the squad plus the lightweight team profile that
/// rides along in ESPN's roster payload. Bundled so one network call feeds the
/// whole team page — colored player cards AND the pinned header's standing line.
struct ClubSquad {
    let athletes: [Athlete]
    let colorHex: String?          // ESPN team color, e.g. "C8102E"
    let standingSummary: String?   // e.g. "4th in NWSL"
    let record: String?            // W-D-L, e.g. "6-3-2"

    /// League points derived from the W-D-L record (3 per win, 1 per draw).
    /// nil when the record is missing or unparseable, so the header can degrade.
    var points: Int? {
        guard let record else { return nil }
        let parts = record.split(separator: "-").map { Int($0) }
        guard parts.count == 3, let wins = parts[0], let draws = parts[1] else { return nil }
        return wins * 3 + draws
    }

    /// The pinned-header line: "4th in NWSL — 21 pts" (or just the summary when
    /// points can't be derived). nil when there's no standing summary at all.
    var standingLine: String? {
        guard let standingSummary else { return nil }
        if let points { return "\(standingSummary) — \(points) pts" }
        return standingSummary
    }
}

// MARK: - Position grouping

/// Roster presentation helpers — squads read best grouped by position in a fixed
/// soccer order (keepers first), not alphabetically.
enum Roster {
    /// One position bucket for a List section (e.g. "Goalkeepers" → its players).
    struct PositionGroup: Identifiable {
        let id: String        // the raw position name, stable for ForEach
        let label: String     // pluralized section title
        let athletes: [Athlete]
    }

    // Fixed display order; anything ESPN returns outside this set is appended.
    // Attackers lead: the Teams "Squad" tab is a "meet the team" experience, and
    // the players fans come to see (forwards) front the grid (per the design spec).
    private static let order = ["Forward", "Midfielder", "Defender", "Goalkeeper"]
    private static let plurals = [
        "Goalkeeper": "Goalkeepers",
        "Defender": "Defenders",
        "Midfielder": "Midfielders",
        "Forward": "Forwards",
    ]

    /// Group athletes by position, ordered FWD → MID → DEF → GK (unknowns last,
    /// alphabetically), each bucket sorted by jersey number.
    static func grouped(_ athletes: [Athlete]) -> [PositionGroup] {
        let buckets = Dictionary(grouping: athletes) { $0.positionName ?? "Other" }
        return buckets
            .map { name, players in
                PositionGroup(
                    id: name,
                    label: plurals[name] ?? name,
                    athletes: players.sorted { jerseyValue($0.jersey) < jerseyValue($1.jersey) }
                )
            }
            .sorted { rank(of: $0.id) < rank(of: $1.id) }
    }

    // Known positions sort by their index; unknowns sort after, alphabetically
    // (offset keeps them past the known set without colliding).
    private static func rank(of position: String) -> (Int, String) {
        if let index = order.firstIndex(of: position) { return (index, "") }
        return (order.count, position)
    }

    // Numeric jersey sort; missing/non-numeric jerseys sink to the bottom.
    private static func jerseyValue(_ jersey: String?) -> Int {
        guard let jersey, let number = Int(jersey) else { return Int.max }
        return number
    }
}

// MARK: - ESPN roster endpoint decoding
//
// Payload shape (trimmed to what we use):
//   { "team": { "color": "C8102E", "standingSummary": "4th in NWSL",
//               "recordSummary": "6-3-2" },
//     "athletes": [ {
//       "id": "211963", "fullName": "Hannah Seabert", "shortName": "H. Seabert",
//       "jersey": "13",
//       "position": { "displayName": "Goalkeeper", "abbreviation": "G" },
//       "age": 31, "displayHeight": "5' 10\"", "citizenship": "USA",
//       "headshot": { "href": ... }   // null for NWSL
//   } ] }

struct RosterResponse: Decodable {
    let team: RawTeam?
    let athletes: [RawAthlete]?

    /// The squad plus the team profile that rides along in the same payload.
    var squad: ClubSquad {
        ClubSquad(
            athletes: players,
            colorHex: team?.color,
            standingSummary: team?.standingSummary,
            record: team?.recordSummary
        )
    }

    /// Flatten to view-friendly athletes, dropping any entry without an id.
    var players: [Athlete] {
        (athletes ?? []).compactMap { raw -> Athlete? in
            guard let id = raw.id else { return nil }
            return Athlete(
                id: id,
                name: raw.fullName ?? raw.displayName ?? "—",
                shortName: raw.shortName,
                jersey: raw.jersey,
                positionName: raw.position?.displayName,
                positionAbbreviation: raw.position?.abbreviation,
                age: raw.age,
                displayHeight: raw.displayHeight,
                citizenship: raw.citizenship
            )
        }
    }

    // The team profile carried alongside the roster (color for accents, the
    // standing line for the header). All optional — ESPN is unofficial.
    struct RawTeam: Decodable {
        let color: String?
        let standingSummary: String?
        let recordSummary: String?
    }

    struct RawAthlete: Decodable {
        let id: String?
        let fullName: String?
        let displayName: String?
        let shortName: String?
        let jersey: String?
        let position: RawPosition?
        let age: Int?
        let displayHeight: String?
        let citizenship: String?
        // Decoded but intentionally unused — null for NWSL (see file header).
        let headshot: Headshot?
    }

    struct RawPosition: Decodable {
        let displayName: String?
        let abbreviation: String?
    }

    struct Headshot: Decodable { let href: String? }
}
