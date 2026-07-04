//
//  MatchSummary.swift
//  NWSLApp
//
//  Decodes ESPN's unofficial per-event `/summary` endpoint:
//    https://site.api.espn.com/apis/site/v2/sports/soccer/usa.nwsl/summary?event={id}
//
//  This is the richer counterpart to the scoreboard `Event` (Scoreboard.swift):
//  the scoreboard gives every match's score/venue/status in one season-wide
//  fetch, while `/summary` is one match at a time — lineups (with formation),
//  team match stats (the boxscore), and a key-events timeline (goals, cards,
//  subs). MatchDetailView fetches it on demand for a single tapped match.
//
//  As with Scoreboard, ESPN is unofficial and its NWSL feed has gaps, so EVERY
//  field is optional or defaulted — a missing field should degrade the screen,
//  never crash it. We decode only the slice the UI uses (the real response also
//  carries odds, news, videos, commentary, etc., which Decodable simply ignores).
//
//  Type quirks verified against a real 2026 response (see the decode test +
//  NWSLAppTests/Fixtures/summary.json):
//   - `jersey` and `formationPlace` arrive as Strings ("18", "1"), not Ints.
//   - Player jersey/position live on the roster *player*, not on `athlete`.
//   - A boxscore stat's numeric `value` can be null (only `displayValue` is safe).
//

import Foundation

struct MatchSummary: Decodable {
    let boxscore: Boxscore?
    let rosters: [MatchRoster]?
    let keyEvents: [KeyEvent]?
    let gameInfo: GameInfo?
}

// MARK: - Boxscore (team-level match stats)

struct Boxscore: Decodable {
    let teams: [BoxscoreTeam]?
}

struct BoxscoreTeam: Decodable {
    let homeAway: String?            // "home" | "away"
    let team: BoxscoreTeamInfo?
    let statistics: [BoxscoreStat]?
}

struct BoxscoreTeamInfo: Decodable {
    let id: String?
    let abbreviation: String?
    let displayName: String?
    let color: String?               // hex without '#', e.g. "000000"
    let alternateColor: String?
    let logo: String?
}

/// One team-level stat. `name` is the stable camelCase key we match on
/// ("possessionPct", "totalShots", …); `label` is ESPN's human label ("Possession");
/// `displayValue` is the presentational string ("61", "0.9"). `value` (the raw
/// Double) can be null, so bar widths must tolerate its absence.
struct BoxscoreStat: Decodable {
    let name: String?
    let label: String?
    let displayValue: String?
    let value: Double?
}

// MARK: - Rosters (lineups + formation)

struct MatchRoster: Decodable {
    let homeAway: String?            // "home" | "away"
    let formation: String?           // e.g. "4-2-3-1", "3-4-3"
    let winner: Bool?
    let team: MatchRosterTeam?
    let roster: [MatchPlayer]?
}

struct MatchRosterTeam: Decodable {
    let id: String?
    let abbreviation: String?
    let displayName: String?
    let color: String?               // hex without '#'
    let alternateColor: String?
}

struct MatchPlayer: Decodable {
    let athlete: MatchAthlete?
    let jersey: String?              // ESPN sends as String ("18")
    let position: MatchPosition?
    let starter: Bool?
    let formationPlace: String?      // ESPN sends as String ("1"–"11")
    let subbedIn: SubStatus?
    let subbedOut: SubStatus?
    let active: Bool?                // false ≈ unused sub (no `didNotPlay` key exists)
}

/// ESPN's sub flags are shape-inconsistent across feeds: a LIVE match's `/summary`
/// sends an OBJECT (`{"didSub": false}`), while other snapshots may send a bare Bool.
/// Decoding only one shape throws a `DecodingError` that fails the ENTIRE
/// `MatchSummary` — the "Couldn't read the match details" bug that hid a live match's
/// full lineups. So we accept BOTH (and any unknown shape → `didSub == false`) and
/// let callers read `.didSub`.
struct SubStatus: Decodable {
    let didSub: Bool

    private struct Object: Decodable { let didSub: Bool? }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let flag = try? container.decode(Bool.self) {
            didSub = flag
        } else {
            didSub = (try? container.decode(Object.self))?.didSub ?? false
        }
    }
}

struct MatchAthlete: Decodable {
    let id: String?
    let displayName: String?
    let shortName: String?
    let lastName: String?
}

struct MatchPosition: Decodable {
    let name: String?                // "Goalkeeper", "Defender", …
    let displayName: String?
    let abbreviation: String?        // "G", "D", "M", "F"
}

// MARK: - Key events (timeline)

struct KeyEvent: Decodable {
    let id: String?
    let type: KeyEventType?
    let clock: KeyEventClock?
    let scoringPlay: Bool?
    let team: KeyEventTeam?          // null on neutral events (e.g. kickoff)
    let participants: [KeyEventParticipant]?
}

struct KeyEventType: Decodable {
    let id: String?
    let text: String?                // "Goal", "Yellow Card", "Substitution", …
    let type: String?                // "goal", "yellow-card", "substitution", …
}

struct KeyEventClock: Decodable {
    let value: Double?
    let displayValue: String?        // "52'", "90'+3'", …
}

struct KeyEventTeam: Decodable {
    let id: String?
    let displayName: String?
}

/// For a goal, `participants[0]` is the scorer and a later entry the assist;
/// for a sub, the player on / player off. We keep the array as-is and let the
/// view label by position.
struct KeyEventParticipant: Decodable {
    let athlete: MatchAthlete?
}

// MARK: - Game info

struct GameInfo: Decodable {
    let venue: GameInfoVenue?
    let attendance: Int?
    let officials: [GameInfoOfficial]?
}

/// A match official. ESPN's NWSL feed gives a name + an order index but no
/// role/position, so we can't distinguish referee from assistant.
struct GameInfoOfficial: Decodable {
    let displayName: String?
    let fullName: String?
    let order: Int?
}

struct GameInfoVenue: Decodable {
    let fullName: String?
    let address: Address?

    struct Address: Decodable {
        let city: String?
        let country: String?
    }
}

// MARK: - Helpers
//
// Derived accessors so views read intent ("home roster", "the starters") rather
// than re-implementing the homeAway split / formationPlace parse each time.

extension MatchSummary {
    var homeRoster: MatchRoster? { rosters?.first { $0.homeAway == "home" } }
    var awayRoster: MatchRoster? { rosters?.first { $0.homeAway == "away" } }

    var homeBoxscore: BoxscoreTeam? { boxscore?.teams?.first { $0.homeAway == "home" } }
    var awayBoxscore: BoxscoreTeam? { boxscore?.teams?.first { $0.homeAway == "away" } }

    /// Goals/cards/subs only, in chronological order — drops neutral markers
    /// like "Kickoff"/"End of …" that carry no participant.
    var timelineEvents: [KeyEvent] {
        (keyEvents ?? [])
            .filter { ($0.participants?.isEmpty == false) || ($0.scoringPlay == true) }
            .sorted { ($0.clock?.value ?? 0) < ($1.clock?.value ?? 0) }
    }
}

extension MatchRoster {
    /// Starters in formation order (place 1 = GK … 11). Players without a
    /// usable place sort last, so a partial feed still renders.
    var starters: [MatchPlayer] {
        (roster ?? [])
            .filter { $0.starter == true }
            .sorted { ($0.formationPlaceValue ?? .max) < ($1.formationPlaceValue ?? .max) }
    }

    /// Everyone who started on the bench (subs + unused), in the feed's order.
    var substitutes: [MatchPlayer] {
        (roster ?? []).filter { $0.starter != true }
    }
}

extension MatchPlayer {
    /// Did this player come on / go off — reading through the shape-tolerant `SubStatus`.
    var didSubIn: Bool { subbedIn?.didSub == true }
    var didSubOut: Bool { subbedOut?.didSub == true }

    /// `formationPlace` parsed to Int (ESPN sends it as a String).
    var formationPlaceValue: Int? {
        guard let formationPlace else { return nil }
        return Int(formationPlace)
    }

    /// Short label for the player, preferring ESPN's abbreviated form.
    var displayLabel: String {
        athlete?.shortName ?? athlete?.displayName ?? athlete?.lastName ?? "—"
    }
}

extension BoxscoreTeam {
    /// Look up a stat by its stable `name` key (e.g. "possessionPct").
    func stat(_ name: String) -> BoxscoreStat? {
        statistics?.first { $0.name == name }
    }
}
