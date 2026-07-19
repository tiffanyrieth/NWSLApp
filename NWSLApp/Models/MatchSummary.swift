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
    let commentary: [Commentary]?
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

// MARK: - Commentary (the FULL play-by-play)
//
// `keyEvents` is ESPN's abbreviated set (goals/cards/subs). The SAME /summary response
// also carries a `commentary` array — the complete play-by-play: shots, saves (shot on
// target), fouls, corners, offsides, VAR, etc. Each item has a minute + a typed play +
// the team by DISPLAY NAME (no id/abbr) + descriptive text. Reuses KeyEventType/
// KeyEventClock (identical shapes) to stay lean.

struct Commentary: Decodable {
    let sequence: Int?
    let time: CommentaryTime?        // top-level minute ("56'")
    let text: String?                // the descriptive sentence
    let play: CommentaryPlay?
}

struct CommentaryTime: Decodable {
    let value: Double?               // seconds — sort key
    let displayValue: String?        // "56'", "90'+1'"
}

struct CommentaryPlay: Decodable {
    let type: KeyEventType?          // .type is the stable slug ("shot-on-target", "foul", …)
    let text: String?
    let shortText: String?
    let clock: KeyEventClock?
    let team: CommentaryTeam?        // DISPLAY NAME only — no id (map to home/away by name)
}

struct CommentaryTeam: Decodable {
    let displayName: String?
}

// MARK: - Unified play-by-play row model
//
// One list feeding the Play-by-Play tab: the rich goal/card/sub rows come from `keyEvents`
// (structured scorer/assist + running scoreline, unchanged), the extra types come from
// `commentary` (label + ESPN text). Merged and sorted newest-first. `EventTimelineRow`
// renders these; the view resolves crest/color per row from `isHome`.

enum PlayKind {
    case goal, yellowCard, redCard, substitution   // from keyEvents (enriched)
    case shotOnTarget, shotOffTarget, shotBlocked   // from commentary
    case foul, corner, offside, varReview, other

    var isGoal: Bool { self == .goal }

    /// Display label for the commentary-only kinds (the enriched kinds use the scorer name).
    var label: String {
        switch self {
        case .shotOnTarget: return "Shot on target"
        case .shotOffTarget: return "Shot off target"
        case .shotBlocked: return "Shot blocked"
        case .foul: return "Foul"
        case .corner: return "Corner"
        case .offside: return "Offside"
        case .varReview: return "VAR review"
        default: return ""
        }
    }
}

struct PlayByPlayItem: Identifiable {
    let id: String
    let sortValue: Double            // clock seconds — merge/order key
    let minute: String               // "56'" or "—"
    let kind: PlayKind
    let isHome: Bool
    let primary: String              // scorer name (enriched) or the kind label
    let detail: String?              // assist / "on for X" / card text / commentary sentence
    let score: String?               // running scoreline on a goal, e.g. "1–0"
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

    /// The FULL play-by-play, newest-first. Rich goal/card/sub rows come from `keyEvents`
    /// (structured scorer/assist + running scoreline); the extra types (shots/fouls/corners/
    /// offsides/VAR) come from `commentary`. The two are MERGED and sorted by clock — no
    /// dedup needed because commentary's goal/card/sub/neutral slugs are excluded (they're the
    /// keyEvents rows). `homeID` credits goals to a side; `homeDisplayName` maps a commentary
    /// item (which names its team by display name only) to home vs away.
    func playByPlay(homeID: String?, homeDisplayName: String?) -> [PlayByPlayItem] {
        var items: [PlayByPlayItem] = []

        // A) keyEvents — goals/cards/subs, enriched, with the running scoreline (ascending pass).
        var home = 0, away = 0
        for (i, ev) in timelineEvents.enumerated() {
            let isHome = ev.team?.id == homeID
            let kind = Self.keyEventKind(ev)
            var score: String? = nil
            if kind == .goal {
                if isHome { home += 1 } else { away += 1 }
                score = "\(home)\u{2013}\(away)"   // en dash
            }
            items.append(PlayByPlayItem(
                id: "k-\(ev.id ?? "\(i)")-\(i)",
                sortValue: ev.clock?.value ?? 0,
                minute: ev.clock?.displayValue?.nonEmpty ?? "—",
                kind: kind,
                isHome: isHome,
                primary: Self.keyEventPrimary(ev),
                detail: Self.keyEventDetail(ev, kind: kind),
                score: score))
        }

        // B) commentary — ONLY the extra types (goal/card/sub/neutral slugs → nil, skipped).
        for c in (commentary ?? []) {
            guard let kind = Self.commentaryKind(c.play?.type?.type) else { continue }
            items.append(PlayByPlayItem(
                id: "c-\(c.sequence ?? Int(c.time?.value ?? 0))",
                sortValue: c.play?.clock?.value ?? c.time?.value ?? 0,
                minute: (c.time?.displayValue ?? c.play?.clock?.displayValue)?.nonEmpty ?? "—",
                kind: kind,
                isHome: c.play?.team?.displayName == homeDisplayName,
                primary: kind.label,
                detail: c.text?.nonEmpty,
                score: nil))
        }

        return items.sorted { $0.sortValue > $1.sortValue }   // newest-first
    }

    /// Classify a keyEvent (goals/cards/subs). Goal FIRST via the authoritative `scoringPlay`
    /// flag (covers penalties/own goals), then EXACT slug matches — never loose `contains("red")`
    /// (that drew scored penalties, slug "penalty---scoRED", as red cards; owner caught it live).
    private static func keyEventKind(_ ev: KeyEvent) -> PlayKind {
        if ev.scoringPlay == true || (ev.type?.type ?? "").contains("goal") { return .goal }
        let t = ev.type?.type ?? ""
        if t.contains("yellow-card") { return .yellowCard }
        if t.contains("red-card") { return .redCard }
        if t.contains("substitution") { return .substitution }
        return .other
    }

    /// Map a commentary slug to a kind, or nil to SKIP: the goal/card/sub slugs (already shown
    /// as the richer keyEvents rows) and neutral markers (kickoff/halftime/delays/aerial).
    private static func commentaryKind(_ slug: String?) -> PlayKind? {
        switch slug {
        case "shot-on-target": return .shotOnTarget
        case "shot-off-target": return .shotOffTarget
        case "shot-blocked": return .shotBlocked
        case "foul": return .foul
        case "corner-awarded": return .corner
        case "offside": return .offside
        case let s? where s.contains("var") || s == "deleted-after-review": return .varReview
        default: return nil
        }
    }

    private static func keyEventNames(_ ev: KeyEvent) -> [String] {
        (ev.participants ?? []).compactMap { $0.athlete?.displayName }
    }

    private static func keyEventPrimary(_ ev: KeyEvent) -> String {
        keyEventNames(ev).first ?? ev.type?.text ?? "—"
    }

    /// Assist for a goal, "on for {out}" for a sub (ESPN lists [in, out]), card text otherwise.
    private static func keyEventDetail(_ ev: KeyEvent, kind: PlayKind) -> String? {
        let names = keyEventNames(ev)
        guard names.count > 1 else {
            return (kind == .yellowCard || kind == .redCard) ? ev.type?.text : nil
        }
        switch kind {
        case .goal: return "Assist: \(names[1])"
        case .substitution: return "on for \(names[1])"
        default: return names.dropFirst().joined(separator: ", ")
        }
    }
}

private extension String {
    /// The string, or nil when empty — so "" collapses to a real absence.
    var nonEmpty: String? { isEmpty ? nil : self }
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
