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
//  null for every NWSL athlete, so we don't model or render a photo — PlayerRow
//  shows a jersey-number / initials monogram instead. This is a deliberate,
//  permanent decision for this league, not a TODO.
//

import Foundation

/// One player, flattened from ESPN's roster payload for the view layer.
struct Athlete: Identifiable, Hashable {
    let id: String
    let name: String
    let jersey: String?            // ESPN sends jersey as a String ("13"), like scores
    let positionName: String?      // "Goalkeeper", "Defender", …
    let positionAbbreviation: String?  // "G", "D", "M", "F"
    let age: Int?
    let displayHeight: String?     // e.g. "5' 10\""
    let citizenship: String?       // e.g. "USA"
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
    private static let order = ["Goalkeeper", "Defender", "Midfielder", "Forward"]
    private static let plurals = [
        "Goalkeeper": "Goalkeepers",
        "Defender": "Defenders",
        "Midfielder": "Midfielders",
        "Forward": "Forwards",
    ]

    /// Group athletes by position, ordered GK → DEF → MID → FWD (unknowns last,
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
//   { "athletes": [ {
//       "id": "211963", "fullName": "Hannah Seabert", "jersey": "13",
//       "position": { "displayName": "Goalkeeper", "abbreviation": "G" },
//       "age": 31, "displayHeight": "5' 10\"", "citizenship": "USA",
//       "headshot": { "href": ... }   // null for NWSL
//   } ] }

struct RosterResponse: Decodable {
    let athletes: [RawAthlete]?

    /// Flatten to view-friendly athletes, dropping any entry without an id.
    var players: [Athlete] {
        (athletes ?? []).compactMap { raw -> Athlete? in
            guard let id = raw.id else { return nil }
            return Athlete(
                id: id,
                name: raw.fullName ?? raw.displayName ?? "—",
                jersey: raw.jersey,
                positionName: raw.position?.displayName,
                positionAbbreviation: raw.position?.abbreviation,
                age: raw.age,
                displayHeight: raw.displayHeight,
                citizenship: raw.citizenship
            )
        }
    }

    struct RawAthlete: Decodable {
        let id: String?
        let fullName: String?
        let displayName: String?
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
