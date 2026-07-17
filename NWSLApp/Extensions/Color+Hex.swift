//
//  Color+Hex.swift
//  NWSLApp
//
//  Turns ESPN's team-color hex strings (e.g. "C8102E") into SwiftUI Colors.
//  ESPN gives each club a primary color in the roster/teams payloads; the Teams
//  tab uses it to accent player cards and jersey badges (see the design spec).
//
//  `teamAccent(hex:)` returns both the fill AND a readable foreground (black or
//  white) chosen by perceived luminance, so a number drawn on a club's color is
//  always legible — light on dark clubs, dark on light ones. When the hex is
//  missing or malformed it falls back to the app accent rather than rendering a
//  wrong (or invisible) swatch — ESPN is unofficial, so a bad value should
//  degrade, not crash.
//

import SwiftUI

/// A team's resolved match color: a `fill` that always reads on the dark canvas
/// and is distinct from the opponent's, plus a legible `onText` (black/white) to
/// draw a jersey number on top of it. Produced by `Color.resolveMatchColors`.
struct ResolvedTeamColor {
    let fill: Color
    let onText: Color
}

extension Color {
    /// Build a Color from a 6-digit hex string ("#RRGGBB" or "RRGGBB"). Used by
    /// the design-token layer (`DSColor`), which passes known-good constants;
    /// a malformed string degrades to `.clear` rather than crashing. Reuses the
    /// same parser as the team-color helpers below (no second hex parser).
    init(hex: String) {
        if let rgb = Color.rgbComponents(hex) {
            self = Color(red: rgb.r, green: rgb.g, blue: rgb.b)
        } else {
            self = .clear
        }
    }

    /// A team's accent color plus a legible foreground to draw on top of it.
    /// Falls back to `(.accentColor, .white)` for missing/malformed hex.
    static func teamAccent(hex: String?) -> (fill: Color, on: Color) {
        guard let rgb = rgbComponents(hex) else { return (.accentColor, .white) }
        // Perceived luminance (Rec. 601): dark fills get white text, light fills black.
        let luminance = 0.299 * rgb.r + 0.587 * rgb.g + 0.114 * rgb.b
        return (Color(red: rgb.r, green: rgb.g, blue: rgb.b), luminance < 0.6 ? .white : .black)
    }

    /// A team color guaranteed to read as a fill/bar on the app's dark
    /// background: very dark hues (e.g. a club whose primary is black or navy)
    /// are lifted toward a lighter tint so the fill never disappears, while
    /// already-bright colors pass through unchanged. Falls back to the app accent
    /// for missing/malformed hex. Use this (not the raw fill) for bars and dots
    /// drawn directly on the dark canvas.
    static func teamFillOnDark(hex: String?) -> Color {
        guard let rgb = rgbComponents(hex) else { return .accentColor }
        let luminance = 0.299 * rgb.r + 0.587 * rgb.g + 0.114 * rgb.b
        guard luminance < 0.35 else {
            return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
        }
        // Blend toward white so black/near-black brand colors stay visible.
        let lift = 0.45
        return Color(
            red: rgb.r + (1 - rgb.r) * lift,
            green: rgb.g + (1 - rgb.g) * lift,
            blue: rgb.b + (1 - rgb.b) * lift
        )
    }

    /// The ONE team-accent resolver: an abbreviation → its brand color, via the design
    /// palette (`DesignTeamColors.displayHex`) lifted for the dark canvas
    /// (`teamFillOnDark`). Replaces ~7 copy-pasted `displayHex → teamFillOnDark` helpers
    /// that had drifted on their fallbacks (gray vs `.dsAccent`) and their lift behavior.
    ///
    /// - `liftOnDark`: apply the on-dark lift (default). Pass `false` for callers drawing on
    ///   a LIGHT surface — lifting toward white there would *reduce* contrast (e.g. the
    ///   Know Her Game rows on a grouped background).
    /// - `fallback`: color when the abbreviation isn't in any palette. Defaults to the
    ///   neutral `.dsFgSecondary` token (#8E8E93) — the same gray these sites hardcoded.
    static func teamColor(
        for abbreviation: String?,
        liftOnDark: Bool = true,
        fallback: Color = .dsFgSecondary
    ) -> Color {
        guard let hex = DesignTeamColors.displayHex(for: abbreviation) else { return fallback }
        return liftOnDark ? Color.teamFillOnDark(hex: hex) : Color(hex: hex)
    }

    /// Convenience for scoreboard callers holding a `Competitor` (reads its team abbreviation).
    static func teamColor(
        for competitor: Competitor?,
        liftOnDark: Bool = true,
        fallback: Color = .dsFgSecondary
    ) -> Color {
        teamColor(for: competitor?.team?.abbreviation, liftOnDark: liftOnDark, fallback: fallback)
    }

    // MARK: - Match color resolution
    //
    // The two teams in a match show their colors side-by-side everywhere (formation
    // dots, stat bars + values, the stats header, the header wash). Two problems
    // ESPN's raw hexes cause on a dark canvas: a near-black primary (several NWSL
    // clubs are #000000 / near-black) disappears, and two such clubs both lifted
    // toward white collapse to the *same* gray — destroying which-team-is-which.
    // `resolveMatchColors` fixes both, once, so every callsite shares the answer.

    private struct RGB { let r, g, b: Double }
    // Distinct defaults when a team has no usable hex at all, kept far apart.
    private static let fallbackHome = RGB(r: 0.20, g: 0.48, b: 0.90)   // blue
    private static let fallbackAway = RGB(r: 0.95, g: 0.45, b: 0.10)   // orange

    /// Resolve both teams' display colors for a match: each legible on dark, and
    /// guaranteed visibly distinct from each other. Pass ESPN's primary + alternate
    /// hex for each side (any may be nil/malformed).
    static func resolveMatchColors(
        homePrimary: String?, homeAlt: String?,
        awayPrimary: String?, awayAlt: String?
    ) -> (home: ResolvedTeamColor, away: ResolvedTeamColor) {
        let (home, away) = matchRGBs(homePrimary: homePrimary, homeAlt: homeAlt,
                                     awayPrimary: awayPrimary, awayAlt: awayAlt)
        return (resolved(home), resolved(away))
    }

    /// The core resolution (raw RGB) shared by the public color API and tests.
    private static func matchRGBs(
        homePrimary: String?, homeAlt: String?,
        awayPrimary: String?, awayAlt: String?
    ) -> (home: RGB, away: RGB) {
        let home = displayRGB(primary: homePrimary, alt: homeAlt, fallback: fallbackHome)
        var away = displayRGB(primary: awayPrimary, alt: awayAlt, fallback: fallbackAway)

        // Safety net: if the two chosen colors are still too close, try the away
        // team's alternate; if that's no better, shift its lightness away from home.
        if distance(home, away) < 0.30 {
            if let alt = rgb(from: awayAlt).map(ensureVisible), distance(home, alt) >= 0.30 {
                away = alt
            } else {
                away = shiftLightness(away, awayFrom: home)
            }
        }
        return (home, away)
    }

    #if DEBUG
    /// Testing seam: the resolved colors as raw (r,g,b) + their separation, so a
    /// unit test can assert the two teams end up visibly distinct.
    static func _resolveMatchRGBForTesting(
        homePrimary: String?, homeAlt: String?,
        awayPrimary: String?, awayAlt: String?
    ) -> (home: (r: Double, g: Double, b: Double), away: (r: Double, g: Double, b: Double), separation: Double) {
        let (h, a) = matchRGBs(homePrimary: homePrimary, homeAlt: homeAlt,
                               awayPrimary: awayPrimary, awayAlt: awayAlt)
        return ((h.r, h.g, h.b), (a.r, a.g, a.b), distance(h, a))
    }
    #endif

    /// Pick a team's display color: the primary if it reads on dark, else a
    /// bright-enough alternate, else the primary/alternate lifted, else fallback.
    private static func displayRGB(primary: String?, alt: String?, fallback: RGB) -> RGB {
        let p = rgb(from: primary)
        let a = rgb(from: alt)
        if let p, brightness(p) >= 0.22 { return p }
        if let a, brightness(a) >= 0.22 { return a }
        if let p { return lift(p) }
        if let a { return lift(a) }
        return fallback
    }

    private static func resolved(_ rgb: RGB) -> ResolvedTeamColor {
        ResolvedTeamColor(
            fill: Color(red: rgb.r, green: rgb.g, blue: rgb.b),
            // Match teamAccent's 0.6 luminance threshold for the on-color.
            onText: brightness(rgb) < 0.6 ? .white : .black
        )
    }

    private static func ensureVisible(_ rgb: RGB) -> RGB {
        brightness(rgb) >= 0.22 ? rgb : lift(rgb)
    }

    private static func brightness(_ c: RGB) -> Double {
        0.299 * c.r + 0.587 * c.g + 0.114 * c.b   // Rec. 601 perceived luminance
    }

    /// Blend toward white so a near-black brand color stays visible on dark.
    private static func lift(_ c: RGB, _ amount: Double = 0.5) -> RGB {
        blend(c, toward: RGB(r: 1, g: 1, b: 1), amount)
    }

    private static func shiftLightness(_ c: RGB, awayFrom other: RGB) -> RGB {
        // Push opposite the other team's lightness: darken against a light rival,
        // lighten against a dark one.
        let target: RGB = brightness(other) > 0.5 ? RGB(r: 0, g: 0, b: 0) : RGB(r: 1, g: 1, b: 1)
        return blend(c, toward: target, 0.4)
    }

    private static func blend(_ c: RGB, toward t: RGB, _ amount: Double) -> RGB {
        RGB(
            r: c.r + (t.r - c.r) * amount,
            g: c.g + (t.g - c.g) * amount,
            b: c.b + (t.b - c.b) * amount
        )
    }

    private static func distance(_ a: RGB, _ b: RGB) -> Double {
        let dr = a.r - b.r, dg = a.g - b.g, db = a.b - b.b
        return (dr * dr + dg * dg + db * db).squareRoot()
    }

    private static func rgb(from hex: String?) -> RGB? {
        rgbComponents(hex).map { RGB(r: $0.r, g: $0.g, b: $0.b) }
    }

    /// Parse a 6-digit hex string ("RRGGBB", optionally "#"-prefixed) into 0–1
    /// RGB components, or nil if it isn't a clean six hex digits.
    private static func rgbComponents(_ hex: String?) -> (r: Double, g: Double, b: Double)? {
        guard var hex else { return nil }
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = Int(hex, radix: 16) else { return nil }
        return (
            Double((value >> 16) & 0xFF) / 255,
            Double((value >> 8) & 0xFF) / 255,
            Double(value & 0xFF) / 255
        )
    }
}
