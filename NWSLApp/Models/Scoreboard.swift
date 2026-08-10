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
    /// ⚠️ ESPN's own "did this match actually finish" flag, and the ONLY reliable way to tell a
    /// FULL-TIME `post` from an ABANDONED one (2026-07-29). Decoded because `state` alone lies:
    /// a lightning suspension mid-first-half sets `state == "post"` with `completed == false`.
    let completed: Bool?
    /// The status enum, e.g. `STATUS_FULL_TIME` / `STATUS_SUSPENDED` / `STATUS_HALFTIME`. Match on
    /// EXACT values (see `Event.nonFinalPostStatuses`) — never substring-match it (the "scoRED" rule).
    let name: String?

    init(state: String? = nil, description: String? = nil, shortDetail: String? = nil,
         completed: Bool? = nil, name: String? = nil) {
        self.state = state
        self.description = description
        self.shortDetail = shortDetail
        self.completed = completed
        self.name = name
    }
}

struct Competition: Decodable {
    let competitors: [Competitor]?
    // Venue + broadcasts + attendance ride the SAME scoreboard response we already
    // fetch — no extra request. Optional/defensive like everything else here.
    let venue: Venue?
    let broadcasts: [Broadcast]?
    /// Crowd figure for a finished match. ⚠️ 0 is ESPN's "unknown", not a real crowd — consume via
    /// `Event.attendance`, which nils it out. The scoreboard copy of this figure matters because it
    /// refreshes on the live poll, while the `/summary` copy can sit behind a long edge-cache TTL
    /// (the frozen-attendance regression, 2026-08-09).
    let attendance: Int?

    init(competitors: [Competitor]? = nil, venue: Venue? = nil, broadcasts: [Broadcast]? = nil,
         attendance: Int? = nil) {
        self.competitors = competitors
        self.venue = venue
        self.broadcasts = broadcasts
        self.attendance = attendance
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
    /// ESPN's stable team id (e.g. "20905"), the SAME namespace as `Club.id` (from `/teams`) and the
    /// number embedded in the logo URL. Present on scoreboard competitors — it just wasn't decoded
    /// before, which forced the fragile abbreviation join in `MatchStore.matches(for:)`. Optional so a
    /// sparse/NT payload without it still decodes (the join falls back to abbreviation).
    let id: String?
    let displayName: String?
    let abbreviation: String?
    let shortDisplayName: String?
    let logo: String?

    init(id: String? = nil, displayName: String? = nil, abbreviation: String? = nil,
         shortDisplayName: String? = nil, logo: String? = nil) {
        self.id = id
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

    /// ⚠️ `state == "post"` DOES NOT MEAN THE MATCH FINISHED (device-proven 2026-07-29, UTA v WAS
    /// suspended for lightning at 27'). ESPN moves a suspended/abandoned/postponed match to
    /// `post` while setting `completed == false` and `name == "STATUS_SUSPENDED"`. Reading `state`
    /// alone made the app show "Full Time 0–0" mid-first-half — and, far worse, made Predict SCORE
    /// the fixture against that fake final and then never revisit it (a scored fixture leaves
    /// `submittedAwaitingScore` permanently).
    ///
    /// Anything that means "the result is settled" must use this, not `statusState == "post"`.
    static let nonFinalPostStatuses: Set<String> = [
        "STATUS_SUSPENDED", "STATUS_POSTPONED", "STATUS_DELAYED",
        "STATUS_CANCELED", "STATUS_CANCELLED", "STATUS_ABANDONED",
    ]

    /// True only when the match is genuinely settled. Deliberately FAIL-OPEN: a nil `completed`
    /// (an older/sparser payload) does not block, so a feed that omits the flag still scores as
    /// before. Only positive evidence of non-completion — `completed == false`, or an explicit
    /// non-final status name — holds a `post` match back.
    var isFinalResult: Bool {
        guard statusState == "post" else { return false }
        if status?.type?.completed == false { return false }
        if let name = status?.type?.name, Event.nonFinalPostStatuses.contains(name) { return false }
        return true
    }

    /// A `post` match that hasn't actually finished — suspended, abandoned, postponed. Surfaces
    /// honestly instead of a fake FT (`status.type.description` is already ESPN's own label,
    /// e.g. "Suspended", so the UI can just show it).
    var isUnfinishedPost: Bool { statusState == "post" && !isFinalResult }

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

    /// Crowd figure with ESPN's zero-means-unknown rule applied at the model, so every
    /// consumer inherits it. Preferred over the `/summary` copy on match detail: the
    /// scoreboard refreshes on the live poll and self-heals when the count lands late.
    var attendance: Int? {
        (competitions?.first?.attendance).flatMap { $0 > 0 ? $0 : nil }
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
