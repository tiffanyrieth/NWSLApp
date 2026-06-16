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
    /// (then the ESPN value stands). NWSL clubs ONLY — this also doubles as the
    /// "is this an NWSL club?" test in MatchStore's Champions Cup filter, so it must
    /// stay NWSL-scoped. For display color that also covers international sides, use
    /// `displayHex(for:)`.
    static func hex(for abbreviation: String?) -> String? {
        guard let abbreviation else { return nil }
        return palette[abbreviation.uppercased()]
    }

    /// Foreign clubs that appear as Champions Cup opponents (Liga MX Femenil). Kept
    /// SEPARATE from `palette` so it never leaks into the NWSL-membership test; grow it
    /// as new opponents show up (an abbreviation not here just renders neutral gray).
    private static let international: [String: String] = [
        "AME": "FFCC00",  // Club América (Águilas yellow)
        "PAC": "1E4FB0",  // Pachuca (Tuzos blue)
    ]

    /// National-team OPPONENTS (by FIFA code) that aren't in the followable
    /// `NationalTeam` set but show up as opponents in the feeds — so both sides of a
    /// national-team match read in color, not one colored + one gray. National colors,
    /// brightened for the dark canvas. (Followable nations get their color from
    /// `NationalTeam.brandHex`, checked first; CHI is omitted — it collides with the
    /// Chicago Stars abbreviation, which wins as an NWSL club.)
    private static let nationalOpponents: [String: String] = [
        "ARG": "5BA8E0",  // Argentina
        "CHN": "DE2910",  // China
        "CRC": "D62B34",  // Costa Rica
        "GUA": "4997D0",  // Guatemala
        "KEN": "1E9E57",  // Kenya
        "MAR": "C1272D",  // Morocco
        "MWI": "D32F2F",  // Malawi
        "NZL": "5C6F8A",  // New Zealand (black/white → slate so it reads on dark)
        "PAN": "D21034",  // Panama
        "PAR": "D52B1E",  // Paraguay
        "RSA": "1E9E57",  // South Africa
        "RUS": "2E5BE0",  // Russia
        "SLV": "2E5BE0",  // El Salvador
        "VEN": "9E1B32",  // Venezuela
        "VIE": "DA251D",  // Vietnam
        "ZAM": "1E9E57",  // Zambia
    ]

    /// Brand hex for ANY side the app shows, for COLOR rendering only (never the
    /// membership test): NWSL clubs → women's national teams (followable, by FIFA code)
    /// → other national-team opponents → foreign Champions Cup clubs. nil → the caller
    /// renders neutral gray (e.g. a knockout-bracket placeholder like "QFW1").
    static func displayHex(for abbreviation: String?) -> String? {
        guard let abbreviation else { return nil }
        let code = abbreviation.uppercased()
        if let hex = hex(for: abbreviation) { return hex }
        if let nt = NationalTeam.team(code: code) { return nt.brandHex }
        if let hex = nationalOpponents[code] { return hex }
        return international[code]
    }
}
