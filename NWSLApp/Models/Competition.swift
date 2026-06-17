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
    /// A women's national-team match. Payload is the house-style competition label
    /// (e.g. "SheBelieves Cup", "International Friendly", "Concacaf W Gold Cup").
    case international(String)

    /// The tracked-caps competition label shown on the card / match-detail header.
    /// `nil` for NWSL — the design omits it there (it's redundant on the home league).
    var displayLabel: String? {
        switch self {
        case .nwsl:                 return nil
        case .concacafChampionsCup: return "Concacaf W Champions Cup"
        case .international(let l):  return l
        }
    }

    /// NWSL matches keep full team styling; everything else renders the opponent
    /// neutrally and carries a competition badge.
    var isNWSL: Bool {
        if case .nwsl = self { return true }
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
/// World Cup + Olympics are deliberately omitted (the design defers their
/// whole-tournament UI). Copa América Femenina / Arnold Clark slugs can be added once
/// confirmed + allowlisted in the proxy.
/// The CONCACAF W Champions Cup ESPN feed — a CLUB competition (NWSL clubs vs Liga
/// MX et al.). Contrary to the earlier assumption, ESPN DOES carry it under this slug;
/// MatchStore fetches it when the Champions Cup toggle is on and keeps matches that
/// involve an NWSL club (refined to FOLLOWED clubs at the My-teams filter). Joins to
/// clubs by NWSL abbreviation (WAS, GFC — identical across the NWSL + CC feeds).
enum ChampionsCupFeed {
    static let slug = "concacaf.w.champions_cup"
    static let label = "Concacaf W Champions Cup"
}

struct NationalTeamFeed {
    let slug: String
    let label: String

    static let all: [NationalTeamFeed] = [
        .init(slug: "fifa.friendly.w",              label: "International Friendly"),
        .init(slug: "fifa.shebelieves",             label: "SheBelieves Cup"),
        .init(slug: "concacaf.w.gold",              label: "Concacaf W Gold Cup"),
        .init(slug: "concacaf.womens.championship", label: "Concacaf W Championship"),
    ]
}
