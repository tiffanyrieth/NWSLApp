//
//  NationalTeam.swift
//  NWSLApp
//
//  A women's national team the user can follow — a new kind of followable entity
//  that sits alongside clubs in the "My teams" schedule (per the Competitions
//  feature handoff). National teams have no brand color in the system, so they
//  render neutral (accent-blue when followed); their matches are filtered out of the
//  women's national-team ESPN feeds by the team's FIFA `code` (e.g. "USA").
//
//  The list is data, not hardcoded UI: adding a team is one more entry, so the
//  browse-all surface can grow without a code change.
//

import Foundation

struct NationalTeam: Identifiable, Hashable {
    /// Lowercase slug — the stable id persisted in follows ("usa", "mex"…).
    let id: String
    /// FIFA-style display + ESPN match code ("USA", "MEX"). The code is also the
    /// `abbreviation` ESPN's scoreboard competitors carry, so it's the join key that
    /// pulls this team's matches out of the national-team feeds.
    let code: String
    /// Full name ("United States", "Mexico").
    let name: String

    init(_ code: String, _ name: String) {
        self.id = code.lowercased()
        self.code = code
        self.name = name
    }

    /// The 8 featured teams shown in the Competitions view grid.
    static let featured: [NationalTeam] = [
        .init("USA", "United States"),
        .init("MEX", "Mexico"),
        .init("CAN", "Canada"),
        .init("BRA", "Brazil"),
        .init("COL", "Colombia"),
        .init("ENG", "England"),
        .init("JAM", "Jamaica"),
        .init("JPN", "Japan"),
    ]

    /// The full browse-all set (featured + more). A config list — grow it freely.
    static let all: [NationalTeam] = featured + [
        .init("AUS", "Australia"),
        .init("FRA", "France"),
        .init("GER", "Germany"),
        .init("HAI", "Haiti"),
        .init("KOR", "Korea Republic"),
        .init("NGA", "Nigeria"),
        .init("ESP", "Spain"),
        .init("SWE", "Sweden"),
    ]

    /// Lookup by FIFA code (the value persisted in follows + carried on matches).
    static func team(code: String) -> NationalTeam? {
        all.first { $0.code == code }
    }
}
