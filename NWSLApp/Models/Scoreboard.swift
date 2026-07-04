//
//  Scoreboard.swift
//  NWSLApp
//
//  Decodes the response from ESPN's unofficial NWSL scoreboard endpoint:
//    https://site.api.espn.com/apis/site/v2/sports/soccer/usa.nwsl/scoreboard
//
//  These structs mirror the JSON 1:1 (only the fields we currently use).
//  Most properties are optional because ESPN is unofficial and may change
//  shape without warning — a missing field should not break decoding.
//
//  Sample (heavily trimmed) shape:
//    {
//      "events": [
//        {
//          "id": "401853925",
//          "name": "San Diego Wave FC at Chicago Stars FC",
//          "shortName": "SD @ CHI",
//          "date": "2026-05-31T17:00Z",
//          "status": {
//            "displayClock": "90'+17'",
//            "period": 2,
//            "type": { "state": "post", "description": "Full Time", "shortDetail": "FT" }
//          },
//          "competitions": [{
//            "competitors": [
//              { "homeAway": "home", "score": "0",
//                "team": { "displayName": "Chicago Stars FC", "abbreviation": "CHI" } },
//              { "homeAway": "away", "score": "2",
//                "team": { "displayName": "San Diego Wave FC", "abbreviation": "SD" } }
//            ]
//          }]
//        }
//      ]
//    }
//

import Foundation

struct Scoreboard: Decodable {
    let events: [Event]
}

struct Event: Decodable, Identifiable {
    let id: String
    let name: String?
    let shortName: String?
    // Kept as String — ESPN sometimes omits seconds (e.g. "2026-05-31T17:00Z"),
    // which trips the default .iso8601 decoder. The view layer can parse if needed.
    let date: String?
    let status: EventStatus?
    let competitions: [Competition]?
}

struct EventStatus: Decodable {
    let displayClock: String?
    let period: Int?
    let type: StatusType?
    // Match-ELAPSED seconds (ESPN's continuous clock — a 2nd-half value is ~2700–5400,
    // not reset to 0). Powers the app's local football-clock tick (see MatchClock);
    // `displayClock` is ESPN's pre-formatted string, `clock` is the raw number we tick from.
    let clock: Double?

    // Explicit memberwise init with all-nil defaults so decode stays synthesized AND test
    // fixtures / previews can build a status with just the fields they care about.
    init(displayClock: String? = nil, period: Int? = nil, type: StatusType? = nil, clock: Double? = nil) {
        self.displayClock = displayClock
        self.period = period
        self.type = type
        self.clock = clock
    }
}

struct StatusType: Decodable {
    // "pre" | "in" | "post"
    let state: String?
    let description: String?
    let shortDetail: String?
}

struct Competition: Decodable {
    let competitors: [Competitor]?
    // Venue + broadcasts ride the SAME scoreboard response we already fetch — no
    // extra request. Optional/defensive like everything else here.
    let venue: Venue?
    let broadcasts: [Broadcast]?
}

struct Venue: Decodable {
    let fullName: String?
    let address: Address?

    struct Address: Decodable {
        let city: String?
    }
}

struct Broadcast: Decodable {
    // ESPN nests channel names: broadcasts[].names = ["Prime Video"].
    let names: [String]?
}

struct Competitor: Decodable {
    // "home" | "away"
    let homeAway: String?
    // ESPN sends this as a String ("0"), not a number.
    let score: String?
    let team: Team?
}

struct Team: Decodable {
    let displayName: String?
    let abbreviation: String?
    let shortDisplayName: String?
    let logo: String?
}

// MARK: - Event helpers

extension Event {
    // ESPN returns timestamps without seconds (e.g. "2026-05-31T17:00Z"), which
    // trips the default ISO8601DateFormatter. Try both shapes; return nil on miss.
    var kickoff: Date? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        for format in ["yyyy-MM-dd'T'HH:mmZ", "yyyy-MM-dd'T'HH:mm:ssZ"] {
            formatter.dateFormat = format
            if let parsed = formatter.date(from: date) { return parsed }
        }
        return nil
    }

    // "yyyy-MM-dd" in the user's local timezone — group matches by the local
    // day a fan would experience them, not by UTC.
    var dayKey: String? {
        guard let kickoff else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: kickoff)
    }

    var homeCompetitor: Competitor? {
        competitions?.first?.competitors?.first(where: { $0.homeAway == "home" })
    }

    var awayCompetitor: Competitor? {
        competitions?.first?.competitors?.first(where: { $0.homeAway == "away" })
    }

    // "pre" | "in" | "post" | nil
    var statusState: String? { status?.type?.state }

    // Venue name for the match card's info line (pin icon), e.g. "Audi Field".
    var venueName: String? {
        competitions?.first?.venue?.fullName
    }

    // Host city, e.g. "Washington" — paired with venueName on the match detail
    // screen (the card only has room for the venue name).
    var venueCity: String? {
        competitions?.first?.venue?.address?.city
    }

    // First broadcast channel name (TV icon), e.g. "Prime Video". ESPN can list
    // several markets; we surface the first available name.
    var broadcastName: String? {
        competitions?.first?.broadcasts?
            .compactMap { $0.names?.first(where: { !$0.isEmpty }) }
            .first
    }

    // Every broadcast channel ESPN lists (flattened, empties dropped). Used for the
    // Champions Cup Spanish secondary line — where ESPN's feed IS the Spanish feed,
    // these are the real ESPN Deportes / ESPN+ options surfaced under Paramount+.
    var broadcastNames: [String] {
        competitions?.first?.broadcasts?
            .flatMap { $0.names ?? [] }
            .filter { !$0.isEmpty } ?? []
    }
}
