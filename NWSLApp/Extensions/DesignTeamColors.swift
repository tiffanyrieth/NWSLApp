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
        "BAY": "2F80E8",  // Bay FC — brand navy (Pantone 296), brightened for dark-mode legibility (was a placeholder green)
        "BOS": "2FA85A",  // Boston Legacy FC — "Legacy Green", legible on dark (was a placeholder blue)
        "CHI": "6BA4FF",  // Chicago Stars
        "DEN": "239E80",  // Denver Summit FC — "Evergreen" brand primary, brightened for dark-mode pop (was the Sandstone-red accent FF6B4A)
        "GFC": "7FD4C1",  // Gotham FC (ESPN's abbr; the design table's "NJ" was the pre-2021 NY/NJ Sky Blue mark)
        "HOU": "FF8A3D",  // Houston Dash
        "KC": "30C7E8",   // Kansas City Current
        "NC": "E0354B",   // North Carolina Courage (club red — was an unjustified gold override)
        "SEA": "6E7FFF",  // OL Reign / Seattle
        "ORL": "B07CE8",  // Orlando Pride
        "POR": "FF4D6D",  // Portland Thorns (club red — was an unjustified gold override)
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
