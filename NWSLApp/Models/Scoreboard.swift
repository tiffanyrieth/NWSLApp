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
    // ESPN tags every event with its season type: `slug` is "regular-season" or
    // "playoffs---quarterfinals" / "---semifinals" / "---championship". This is the
    // native, free postseason signal the Playoff feature keys on (no clinch math).
    let season: EventSeason?

    // Memberwise init (all defaulted) so the DEBUG postseason simulator + previews can
    // build events in code; Decodable's synthesized `init(from:)` is unaffected.
    init(id: String, name: String? = nil, shortName: String? = nil, date: String? = nil,
         status: EventStatus? = nil, competitions: [Competition]? = nil, season: EventSeason? = nil) {
        self.id = id
        self.name = name
        self.shortName = shortName
        self.date = date
        self.status = status
        self.competitions = competitions
        self.season = season
    }
}

/// ESPN's `event.season` — the season-type tag. `slug` drives postseason detection +
/// round grouping; `type` is ESPN's numeric id (varies per year, so we key on `slug`).
struct EventSeason: Decodable {
    let year: Int?
    let type: Int?
    let slug: String?

    init(year: Int? = nil, type: Int? = nil, slug: String? = nil) {
        self.year = year
        self.type = type
        self.slug = slug
    }
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

    init(state: String? = nil, description: String? = nil, shortDetail: String? = nil) {
        self.state = state
        self.description = description
        self.shortDetail = shortDetail
    }
}

struct Competition: Decodable {
    let competitors: [Competitor]?
    // Venue + broadcasts ride the SAME scoreboard response we already fetch — no
    // extra request. Optional/defensive like everything else here.
    let venue: Venue?
    let broadcasts: [Broadcast]?

    init(competitors: [Competitor]? = nil, venue: Venue? = nil, broadcasts: [Broadcast]? = nil) {
        self.competitors = competitors
        self.venue = venue
        self.broadcasts = broadcasts
    }
}

struct Venue: Decodable {
    let fullName: String?
    let address: Address?

    struct Address: Decodable {
        let city: String?
        init(city: String? = nil) { self.city = city }
    }

    init(fullName: String? = nil, address: Address? = nil) {
        self.fullName = fullName
        self.address = address
    }
}

struct Broadcast: Decodable {
    // ESPN nests channel names: broadcasts[].names = ["Prime Video"].
    let names: [String]?
    init(names: [String]? = nil) { self.names = names }
}

struct Competitor: Decodable {
    // "home" | "away"
    let homeAway: String?
    // ESPN sends this as a String ("0"), not a number.
    let score: String?
    let team: Team?
    // Who advanced — authoritative even on a draw decided by penalties (2025 WAS 1–1 LOU,
    // WAS advanced on PKs). Advancement keys on THIS, never on comparing scores.
    let winner: Bool?

    init(homeAway: String? = nil, score: String? = nil, team: Team? = nil, winner: Bool? = nil) {
        self.homeAway = homeAway
        self.score = score
        self.team = team
        self.winner = winner
    }
}

struct Team: Decodable {
    let displayName: String?
    let abbreviation: String?
    let shortDisplayName: String?
    let logo: String?

    init(displayName: String? = nil, abbreviation: String? = nil,
         shortDisplayName: String? = nil, logo: String? = nil) {
        self.displayName = displayName
        self.abbreviation = abbreviation
        self.shortDisplayName = shortDisplayName
        self.logo = logo
    }
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

    // MARK: Postseason (Playoff feature)

    /// ESPN's season-type slug, e.g. "regular-season" / "playoffs---quarterfinals".
    var seasonSlug: String? { season?.slug }

    /// Any postseason event (`playoffs---*`). The Playoff feature's activation + round
    /// grouping key on this — it's ESPN's native tag, no clinch math.
    var isPlayoffEvent: Bool { season?.slug?.hasPrefix("playoffs") ?? false }

    var isRegularSeasonEvent: Bool { season?.slug == "regular-season" }

    /// The abbreviation of the side ESPN flags as `winner` (authoritative on PK results).
    var winnerAbbreviation: String? {
        competitions?.first?.competitors?
            .first(where: { $0.winner == true })?.team?.abbreviation
    }

    /// ESPN keeps `state == "in"` THROUGH halftime (clock frozen at 2700, description "Halftime").
    /// Every live-clock surface must check this and show a static HT label instead of ticking —
    /// the clock ticking through the break was a live-game bug (2026-07-05, BOS vs BAY).
    var isHalftime: Bool {
        (status?.type?.description ?? "").localizedCaseInsensitiveContains("halftime")
            || status?.type?.shortDetail == "HT"
    }

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
