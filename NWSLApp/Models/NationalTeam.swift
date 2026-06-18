//
//  NationalTeam.swift
//  NWSLApp
//
//  A women's national team the user can follow — a new kind of followable entity
//  that sits alongside clubs in the "My teams" schedule (per the Competitions
//  feature handoff). Each team carries its own identity so the grid cards match the
//  NWSL club-card treatment: a real country flag (the visual anchor), the FIFA code
//  (the text confirmation), and a national brand color that drives the followed-state
//  wash + border + code tint. Matches are filtered out of the women's national-team
//  ESPN feeds by the team's FIFA `code` (e.g. "USA").
//
//  The list is data, not hardcoded UI: adding a team is one more entry (code, name,
//  flag slug, brand hex), so the browse-all surface can grow without a code change.
//

import SwiftUI

struct NationalTeam: Identifiable, Hashable {
    /// Lowercase slug — the stable id persisted in follows ("usa", "mex"…).
    let id: String
    /// FIFA-style display + ESPN match code ("USA", "MEX"). The code is also the
    /// `abbreviation` ESPN's scoreboard competitors carry, so it's the join key that
    /// pulls this team's matches out of the national-team feeds.
    let code: String
    /// Full name ("United States", "Mexico").
    let name: String
    /// flagcdn slug (ISO 3166-1 alpha-2, or a subdivision like "gb-eng" for England) —
    /// builds the flag image URL. ESPN's flag CDN is keyed by per-match team id, not a
    /// clean country code, so the static grid sources flags from flagcdn instead.
    let flagSlug: String
    /// National brand color (hex) — national teams have no ESPN brand color, so this is
    /// curated. Drives the followed-state radial wash + border + the code-chip tint,
    /// mirroring a club's `accentColor`.
    let brandHex: String

    /// For DATA-DRIVEN (Browse-all) teams: ESPN's own country-flag href, keyed by the same FIFA
    /// code that identifies the team (no FIFA→ISO map that could mis-flag a team). nil for the
    /// curated/featured set, which carries a flagcdn `flagSlug` (+ a bundled vector flag on top).
    let flagHref: String?

    init(_ code: String, _ name: String, flag flagSlug: String, color brandHex: String) {
        self.id = code.lowercased()
        self.code = code
        self.name = name
        self.flagSlug = flagSlug
        self.brandHex = brandHex
        self.flagHref = nil
    }

    /// A data-driven team discovered from ESPN coverage (`/national-teams`): flag is ESPN's, color
    /// is the curated national-opponent color when known (`DesignTeamColors.displayHex`) else a
    /// neutral default — so an unfamiliar team still renders, never blank.
    init(discoveredCode code: String, name: String, flag flagHref: String) {
        self.id = code.lowercased()
        self.code = code
        self.name = name
        self.flagSlug = ""
        self.brandHex = DesignTeamColors.displayHex(for: code) ?? "8E8E93"
        self.flagHref = flagHref.isEmpty ? nil : flagHref
    }

    /// The country brand color, mirroring `Club.accentColor`.
    var accentColor: Color { Color(hex: brandHex) }

    /// The flag image URL: ESPN's flag for a data-driven team, else flagcdn (w160 covers the
    /// ≈52pt card mark at Retina; keyless, supports subdivisions like gb-eng). NationalTeamCard
    /// prefers a bundled vector flag over either; this is the download fallback.
    var flagURL: URL? {
        if let flagHref { return URL(string: flagHref) }
        guard !flagSlug.isEmpty else { return nil }
        return URL(string: "https://flagcdn.com/w160/\(flagSlug).png")
    }

    /// The 8 featured teams shown in the Competitions view grid.
    static let featured: [NationalTeam] = [
        .init("USA", "United States", flag: "us",     color: "2E5BE0"),
        .init("MEX", "Mexico",        flag: "mx",     color: "1FA463"),
        .init("CAN", "Canada",        flag: "ca",     color: "E0322B"),
        .init("BRA", "Brazil",        flag: "br",     color: "00A24A"),
        .init("COL", "Colombia",      flag: "co",     color: "F4C20D"),
        .init("ENG", "England",       flag: "gb-eng", color: "E8413A"),
        .init("JAM", "Jamaica",       flag: "jm",     color: "F4C20D"),
        .init("JPN", "Japan",         flag: "jp",     color: "E0322B"),
    ]

    /// The full browse-all set (featured + more). A config list — grow it freely.
    static let all: [NationalTeam] = featured + [
        .init("AUS", "Australia",     flag: "au", color: "F4C20D"),
        .init("FRA", "France",        flag: "fr", color: "2E5BE0"),
        .init("GER", "Germany",       flag: "de", color: "E0322B"),
        .init("HAI", "Haiti",         flag: "ht", color: "2E5BE0"),
        .init("KOR", "Korea Republic",flag: "kr", color: "E0322B"),
        .init("NGA", "Nigeria",       flag: "ng", color: "1FA463"),
        .init("ESP", "Spain",         flag: "es", color: "E8413A"),
        .init("SWE", "Sweden",        flag: "se", color: "3A7BE0"),
    ]

    /// Lookup by FIFA code (the value persisted in follows + carried on matches).
    static func team(code: String) -> NationalTeam? {
        all.first { $0.code == code }
    }
}
