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

extension Color {
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
