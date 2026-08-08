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
        "BOS": "26D07C",  // Boston Legacy FC — official "Emerald" (verified 2026: TruColor/club brand)
        "CHI": "00A3E0",  // Chicago Stars — official "Great Lake" blue (verified 2026)
        "DEN": "239E80",  // Denver Summit FC — "Evergreen" brand primary, brightened for dark-mode pop (was the Sandstone-red accent FF6B4A)
        "GFC": "9ADBE8",  // Gotham FC — official "Sky Blue" (verified 2026; was a mint 7FD4C1 that drifted green)
        "HOU": "FF6900",  // Houston Dash — official "Electric Orange" (verified 2026)
        "KC": "30C7E8",   // Kansas City Current
        "NC": "E0354B",   // North Carolina Courage (club red — was an unjustified gold override)
        "SEA": "6E7FFF",  // OL Reign / Seattle
        "ORL": "B07CE8",  // Orlando Pride
        "POR": "EF3340",  // Portland Thorns — official "Vivid Red" (verified 2026; was FF4D6D which read pink, not red)
        "LOU": "C7A8FF",  // Racing Louisville
        "SD": "FFA400",   // San Diego Wave — official Wave gold (verified 2026; tidied from FFB340)
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

    /// Foreign clubs that appear as Champions Cup opponents. Kept SEPARATE from
    /// `palette` so it never leaks into the NWSL-membership test; grow it per season
    /// as the field changes (an abbreviation not here just renders neutral gray).
    /// ⚠️ Mirrored by the watcher's INTERNATIONAL_HEX (livestate.ts) so the V2 card
    /// wash matches in-app color — keep the two maps identical (synced 2026-08-06).
    private static let international: [String: String] = [
        "AME": "FFCC00",  // Club América (Águilas yellow)
        "PAC": "1E4FB0",  // Pachuca (Tuzos blue)
        "MON": "4D7DD6",  // Monterrey (Rayadas navy, brightened for the dark canvas)
        "ALI": "3E63D4",  // Alianza FC (SLV — royal blue, brightened)
        "ALA": "E03A31",  // LD Alajuelense (CRC — La Liga red)
        "CFC": "FFC61A",  // Chorrillo FC (PAN — crest gold)
        "VAN": "17A3A8",  // Vancouver Rise FC Academy (CAN — Rise teal, brightened)
    ]

    /// National-team colors by FIFA code — the FULL palette, mirrored from the watcher's
    /// `NT_HEX` (`nwslapp-match-watcher/src/livestate.ts`) so a national team reads the SAME color
    /// in the app (schedule / Predict card washes, code chips) as on its V2 Live Activity card.
    /// Curated for the dark canvas — national teams have no ESPN brand color. This SUPERSEDES the
    /// old 16-code `nationalOpponents` subset: a partial list meant some NTs washed and others
    /// rendered gray, which reads as broken (owner 2026-08-08 — the app must be uniform).
    /// ⚠️ CROSS-REPO CONTRACT: keep identical to the watcher's `NT_HEX` (same discipline as the 3 NT
    /// slug lists). CHI/DEN/POR deliberately collide with NWSL club abbreviations — `displayHex` is
    /// club-first (the club wins), `nationalDisplayHex` is NT-first (for national-team matches),
    /// mirroring the watcher's `colorHex` vs `ntColorHex` split.
    private static let nationalTeamHex: [String: String] = [
        "ALB": "DA251C", "ALG": "1E9E57", "AND": "E0322B", "ARG": "5BA8E0", "ARM": "E0322B", "AUS": "F4C20D",
        "AUT": "D72B2C", "AZE": "00A3D6", "BAN": "1E9E57", "BEL": "E0322B", "BIH": "3A6BD6", "BKA": "E0322B",
        "BLR": "E0322B", "BOL": "E0322B", "BRA": "00A24A", "BUL": "00D69D", "CAN": "E0322B", "CHI": "D42E12",
        "CHN": "E0322B", "CIV": "E89000", "CMR": "1E9E57", "COL": "F4C20D", "CPV": "2424B2", "CRC": "D62B34",
        "CRO": "E0322B", "CYP": "F7991D", "CZE": "D7141A", "DEN": "D02A3E", "DOM": "0062D6", "ECU": "FFDD00",
        "EGY": "CE1126", "ENG": "E8413A", "ESP": "E8413A", "EST": "2274B9", "FIN": "3A6BD6", "FRA": "2E5BE0",
        "FRO": "0076D6", "GEO": "E72E3F", "GER": "E0322B", "GHA": "CE2931", "GIB": "E0322B", "GRE": "2A5FAC",
        "GUA": "4997D0", "HAI": "2E5BE0", "HUN": "E0322B", "IND": "F89939", "IRL": "1E9E57", "IRN": "E0322B",
        "ISL": "3A6BD6", "ISR": "2E50A8", "ITA": "3D7CE0", "JAM": "F4C20D", "JPN": "E0322B", "KAZ": "00BDD6",
        "KEN": "1E9E57", "KOR": "E0322B", "KOS": "264FB0", "LIE": "CE1127", "LTU": "FEE000", "LUX": "0099FF",
        "LVA": "E0322B", "MAR": "C1272D", "MDA": "3A6BD6", "MEX": "1FA463", "MKD": "E0322B", "MLI": "FCD116",
        "MLT": "CF142B", "MNE": "E0322B", "MWI": "D32F2F", "NED": "FF7A1A", "NGA": "1FA463", "NIR": "E0322B",
        "NOR": "E0322B", "NZL": "5C6F8A", "PAN": "E0322B", "PAR": "D52B1E", "PER": "E0322B", "PHI": "CE2931",
        "PNG": "E0322B", "POL": "DC143C", "POR": "DA291C", "PRK": "E0322B", "PUR": "E0322B", "ROU": "E0322B",
        "RSA": "1E9E57", "RUS": "2E5BE0", "SCO": "3A6BD6", "SEN": "1E9E57", "SLV": "2E5BE0", "SRB": "C6363C",
        "SUI": "D72B2C", "SVK": "CE1126", "SVN": "E0322B", "SWE": "3A7BE0", "TAN": "00A3DD", "THA": "DD2C33",
        "TPE": "E0322B", "TUR": "E22D34", "UKR": "FFD500", "URU": "3A6BD6", "USA": "2E5BE0", "UZB": "3BA9D6",
        "VEN": "9E1B32", "VIE": "DA251D", "WAL": "E0322B", "ZAM": "1E9E57",
    ]

    /// Brand hex for ANY side the app shows, CLUB-FIRST (color rendering only, never the
    /// membership test): NWSL clubs → national teams → foreign Champions Cup clubs. nil → the
    /// caller renders neutral gray (e.g. a knockout-bracket placeholder like "QFW1"). For a
    /// national-team MATCH use `nationalDisplayHex` so CHI/DEN/POR resolve to the country, not the
    /// colliding NWSL club.
    static func displayHex(for abbreviation: String?) -> String? {
        guard let abbreviation else { return nil }
        let code = abbreviation.uppercased()
        if let hex = hex(for: abbreviation) { return hex }
        if let hex = nationalTeamHex[code] { return hex }
        return international[code]
    }

    /// NT-FIRST color resolver for national-team matches — the national palette wins over a
    /// colliding NWSL club abbreviation (CHI = Chile not Chicago, DEN = Denmark not Denver,
    /// POR = Portugal not Portland). Mirrors the watcher's `ntColorHex`. nil → neutral gray.
    static func nationalDisplayHex(for abbreviation: String?) -> String? {
        guard let abbreviation else { return nil }
        return nationalTeamHex[abbreviation.uppercased()]
    }
}
