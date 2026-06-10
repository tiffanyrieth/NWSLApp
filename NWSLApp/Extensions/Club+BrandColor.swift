//
//  Club+BrandColor.swift
//  NWSLApp
//
//  Bridges the pure `Club` data model (Models/Club.swift — Foundation only) to
//  SwiftUI colors. Kept out of the model itself so Models/ stays UI-free per the
//  app's architecture; this is the design-layer adapter that turns a club's ESPN
//  brand hex into an accent Color, applying the TeamBrandColors override first
//  (for clubs ESPN colors wrong — e.g. Angel City's Sol Rosa coral).
//

import SwiftUI

extension Club {
    /// The club's primary brand hex: the design palette (by abbreviation) wins,
    /// then the TeamBrandColors id-override, then ESPN's raw color. The design
    /// palette is authoritative so near-black ESPN primaries (Spirit, Thorns)
    /// don't lift to gray.
    var brandHex: String? {
        DesignTeamColors.hex(for: abbreviation) ?? TeamBrandColors.primary(for: id) ?? color
    }
    /// The club's alternate brand hex with the override applied.
    var brandAltHex: String? { TeamBrandColors.alternate(for: id) ?? alternateColor }

    /// A single team accent color, guaranteed legible on the dark canvas
    /// (near-black brands are lifted toward white). Used for team-color accents —
    /// Home content/spotlight accent lines, Coming Up abbreviations, etc. (Crests
    /// themselves render bare — a team crest never gets a colored ring.) For the
    /// two colors in a *match*, prefer `Color.resolveMatchColors` (kept distinct).
    var accentColor: Color { Color.teamFillOnDark(hex: brandHex) }
}
