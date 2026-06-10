//
//  DesignTeamColors.swift
//  NWSLApp
//
//  The design handoff's curated 16-team color palette (README "16 NWSL teams with
//  colors" table), keyed by team ABBREVIATION. These are hand-picked to be legible
//  on the dark canvas and recognizable per club — unlike ESPN's raw `color`, which
//  ships several teams a near-black/navy primary (Washington Spirit, Portland, …)
//  that lifts to an indistinct gray.
//
//  This is the authoritative source for a club's accent: `Club.brandHex` consults
//  it first (by abbreviation), then falls back to the ESPN value. Match Detail does
//  the same by the summary's abbreviation, so a team reads the same color in the
//  Home accent lines, Coming Up, and the match header.
//

import Foundation

enum DesignTeamColors {
    /// Abbreviation → brand hex (no '#'). From the design handoff team table.
    private static let palette: [String: String] = [
        "LA": "E6447B",   // Angel City FC
        "BAY": "30D158",  // Bay FC
        "BOS": "5AC8FA",  // Boston
        "CHI": "6BA4FF",  // Chicago Stars
        "DEN": "FF6B4A",  // Denver
        "NJ": "7FD4C1",   // Gotham FC
        "HOU": "FF8A3D",  // Houston Dash
        "KC": "30C7E8",   // Kansas City Current
        "NC": "B79B5B",   // North Carolina Courage
        "SEA": "6E7FFF",  // OL Reign / Seattle
        "ORL": "B07CE8",  // Orlando Pride
        "POR": "E8D26B",  // Portland Thorns
        "LOU": "C7A8FF",  // Racing Louisville
        "SD": "FFB340",   // San Diego Wave
        "UTA": "FFD60A",  // Utah Royals
        "WAS": "FF4D5E",  // Washington Spirit
    ]

    /// The design brand hex for a team abbreviation, or nil if not in the table
    /// (then the ESPN value stands).
    static func hex(for abbreviation: String?) -> String? {
        guard let abbreviation else { return nil }
        return palette[abbreviation.uppercased()]
    }
}
