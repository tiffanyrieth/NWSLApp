//
//  Competition.swift
//  NWSLApp
//
//  The competition-awareness seam for the Schedule. NWSL is the spine; this lets a
//  match also belong to a non-NWSL competition (CONCACAF W Champions Cup, a women's
//  national-team match) so the schedule can weave them into "My teams", label them,
//  and render foreign opponents neutrally.
//
//  Design: tag at MERGE time, not at decode. `Event` (Scoreboard.swift) stays a pure
//  `Decodable` mirror of ESPN's JSON; the fetch layer (MatchStore) wraps each fetched
//  `Event` in a `ScheduledMatch` carrying the competition it was fetched under. This
//  keeps `Event` clean (no optional that's nil for the 99% NWSL path) and leaves the
//  existing abbreviation-join in `MatchStore.matches(for:)` untouched.
//

import Foundation

/// What competition a match belongs to — drives its Schedule chip placement, the
/// competition label on its card, and (later) which data source served it.
///
/// Display names are HOUSE STYLE, mapped on the way in: e.g. the club CONCACAF
/// competition always reads "Concacaf W Champions Cup" regardless of how ESPN (or a
/// curated source) names the feed — see `displayLabel`.
enum CompetitionType: Hashable {
    /// NWSL regular season + playoffs — the spine. No competition label (redundant).
    case nwsl
    /// The CONCACAF W Champions Cup (club continental; NWSL clubs vs Liga MX et al.).
    /// Not a renamed CONCACAF *national-team* tournament — a separate club competition
    /// with no ESPN feed (served from a curated source).
    case concacafChampionsCup
    /// The NWSL Challenge Cup — a single annual match between two NWSL clubs (the prior
    /// season's Shield winner vs Championship winner). ESPN carries it under its own slug
    /// (`usa.nwsl.cup`); NOT the regular season, so it's tagged separately to stay out of
    /// league records/standings/Predict (`isNWSL == false`).
    case challengeCup
    /// A women's national-team match. Payload is the house-style competition label
    /// (e.g. "SheBelieves Cup", "International Friendly", "Concacaf W Gold Cup").
    case international(String)

    /// The tracked-caps competition label shown on the card / match-detail header.
    /// `nil` for NWSL — the design omits it there (it's redundant on the home league).
    var displayLabel: String? {
        switch self {
        case .nwsl:                 return nil
        case .concacafChampionsCup: return "Concacaf W Champions Cup"
        case .challengeCup:         return "NWSL Challenge Cup"
        case .international(let l):  return l
        }
    }

    /// Whether this competition counts toward the LEAGUE TABLE — standings, club
    /// W-D-L records, Predict eligibility — AND keeps full team styling. NWSL regular
    /// season + playoffs only; the Challenge Cup is a one-off that stays out of league
    /// records (see `inNWSLScheduleView` for the separate "shows in the schedule" question).
    var isNWSL: Bool {
        if case .nwsl = self { return true }
        return false
    }

    /// Whether this competition belongs in the Schedule's "NWSL" view. BROADER than
    /// `isNWSL`: the Challenge Cup IS an NWSL competition for SCHEDULE purposes (two NWSL
    /// clubs, NWSL trophy) even though it's excluded from the league table. "Counts in
    /// standings" and "shows in the NWSL schedule" are two different questions — this one
    /// answers the schedule chip; `isNWSL` answers standings/records.
    var inNWSLScheduleView: Bool {
        switch self {
        case .nwsl, .challengeCup:                 return true
        case .concacafChampionsCup, .international: return false
        }
    }

    /// Curated US English-language primary broadcast for competitions ESPN only
    /// carries in Spanish — so ESPN's feed lists only its own Spanish channels
    /// (e.g. ESPN Deportes / ESPN+) and omits the real English home entirely.
    /// CONCACAF club competitions are CBS/Paramount+ English-exclusive in the US
    /// (through 2029-30), so Paramount+ is the universal English home. `nil` =
    /// trust ESPN's `broadcastName`. Revisit if CBS's exclusivity changes.
    var primaryBroadcastOverride: String? {
        switch self {
        case .concacafChampionsCup:              return "Paramount+"
        case .nwsl, .challengeCup, .international: return nil   // ESPN carries the Challenge Cup — trust its broadcastName
        }
    }

    /// Whether to surface ESPN's listed channel(s) as a Spanish-language secondary
    /// option beneath the (overridden) English primary. True only where ESPN's data
    /// IS the Spanish feed, so those channels are genuinely the Spanish alternative.
    var surfacesSpanishSecondary: Bool {
        if case .concacafChampionsCup = self { return true }
        return false
    }
}

/// An ESPN `Event` tagged with the competition it was fetched under. The Schedule
/// filters + labels off this; `id` mirrors the event so SwiftUI identity is stable
/// and cross-feed duplicates (a national-team match in two feeds) dedupe by event id.
struct ScheduledMatch: Identifiable {
    let event: Event
    let competition: CompetitionType
    var id: String { event.id }
}

/// A fetchable women's national-team competition: an ESPN scoreboard `slug` (served
/// via the proxy `?league=` allowlist) + the HOUSE-STYLE `label` its matches carry on
/// the card. After fetching, MatchStore keeps only events involving a FOLLOWED
/// national team (matched by FIFA code), tagging each `.international(label)`.
///
/// These feed BOTH the Schedule "My teams" fold-in (a followed team's fixtures) AND the
/// data-driven Browse-all directory (the proxy `/national-teams` union of each feed's `/teams`)
/// — keep this list in sync with the proxy's `WOMENS_NT_FEEDS`. World Cup + Olympics fold their
/// followed-team MATCHES in (their whole-tournament group/bracket UI is still deferred). Copa
/// América Femenina / Arnold Clark slugs can be added once confirmed + allowlisted in the proxy.
/// The CONCACAF W Champions Cup ESPN feed — a CLUB competition (NWSL clubs vs Liga
/// MX et al.). Contrary to the earlier assumption, ESPN DOES carry it under this slug;
/// MatchStore fetches it when the Champions Cup toggle is on and keeps matches that
/// involve an NWSL club (refined to FOLLOWED clubs at the My-teams filter). Joins to
/// clubs by NWSL abbreviation (WAS, GFC — identical across the NWSL + CC feeds).
enum ChampionsCupFeed {
    static let slug = "concacaf.w.champions_cup"
    static let label = "Concacaf W Champions Cup"
}

/// The NWSL Challenge Cup ESPN feed — slug `usa.nwsl.cup` ("NWSL Challenge Cup"). A single
/// annual NWSL-club-vs-NWSL-club match. UNLIKE the Champions Cup (a global opt-in toggle), this
/// is fetched automatically (no toggle): MatchStore keeps the match and the My-teams filter
/// narrows it to fans of the two participating clubs. Joins by NWSL abbreviation (GFC, KC).
enum ChallengeCupFeed {
    static let slug = "usa.nwsl.cup"
    static let label = "NWSL Challenge Cup"
}

struct NationalTeamFeed {
    let slug: String
    let label: String

    static let all: [NationalTeamFeed] = [
        .init(slug: "fifa.friendly.w",              label: "International Friendly"),
        .init(slug: "fifa.shebelieves",             label: "SheBelieves Cup"),
        .init(slug: "concacaf.w.gold",              label: "Concacaf W Gold Cup"),
        .init(slug: "concacaf.womens.championship", label: "Concacaf W Championship"),
        .init(slug: "uefa.weuro",                   label: "UEFA Women's Euro"),
        .init(slug: "fifa.wwc",                     label: "Women's World Cup"),
        .init(slug: "fifa.w.olympics",              label: "Women's Olympics"),
    ]
}
