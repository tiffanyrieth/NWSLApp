//
//  DSColor.swift
//  NWSLApp
//
//  The app's design-token color palette — the single source of truth for the
//  app-*chrome* colors (backgrounds, surfaces, foregrounds, status, game and
//  match-state accents). Mirrors the design system's `tokens/colors.css`
//  one-to-one (Reference/nwslapp-design-system/tokens/colors.css).
//
//  Scope: these are the FIXED brand/chrome colors. *Team* colors stay dynamic —
//  resolved per club from ESPN hexes via `Color.teamAccent` / `resolveMatchColors`
//  in Color+Hex.swift. Tokens never replace those.
//
//  The app is dark-only (`.preferredColorScheme(.dark)` app-wide), so these are
//  literal hex values rather than light/dark-adaptive system colors — the design
//  specifies exact hues that must not shift. `Color(hex:)` lives in Color+Hex.swift.
//

import SwiftUI

/// Design-token colors. Reference as `Color.dsCard`, `Color.dsFgSecondary`, etc.
extension Color {

    // MARK: Backgrounds (one step lighter than iOS defaults, per the design)
    /// Pure black — the deepest surface (`--color-bg-primary`).
    static let dsBgPrimary = Color(hex: "#000000")
    /// Page background for grouped screens (`--color-bg-grouped`).
    static let dsBgGrouped = Color(hex: "#1C1C1E")
    /// Card / grouped-row surface (`--color-bg-card`).
    static let dsBgCard = Color(hex: "#2C2C2E")
    /// Inset fill inside a card, e.g. the spotlight stat strip (`--color-bg-tertiary`).
    static let dsBgTertiary = Color(hex: "#3A3A3C")

    // MARK: Foregrounds
    static let dsFgPrimary = Color(hex: "#FFFFFF")
    static let dsFgSecondary = Color(hex: "#8E8E93")
    static let dsFgTertiary = Color(hex: "#636366")
    static let dsFgQuaternary = Color(hex: "#48484A")

    // MARK: Accent (iOS system blue — the app accent)
    static let dsAccent = Color(hex: "#0A84FF")
    static let dsAccentMuted = Color(red: 10/255, green: 132/255, blue: 255/255, opacity: 0.18)

    // MARK: Status / feedback
    static let dsLive = Color(hex: "#FF3B30")
    static let dsSuccess = Color(hex: "#30D158")
    static let dsError = Color(hex: "#FF453A")
    static let dsWarning = Color(hex: "#FFD60A")

    // MARK: Followed-team highlight
    /// Blue tint behind a followed-team row (`--color-follow-tint`).
    static let dsFollowTint = Color(red: 0, green: 122/255, blue: 255/255, opacity: 0.10)
    /// The yellow follow star (`--color-follow-star`).
    static let dsFollowStar = Color(hex: "#FFD60A")

    // MARK: Fan Zone game identities
    static let dsGameTrivia = Color(hex: "#5856D6")   // indigo
    static let dsGameBracket = Color(hex: "#30B0C7")  // teal
    static let dsGamePredict = Color(hex: "#FF375F")  // pink

    // MARK: Dividers
    /// Hairline separator used inside cards/rows (`rgba(84,84,88,0.35)`).
    static let dsSeparator = Color(red: 84/255, green: 84/255, blue: 88/255, opacity: 0.35)

    // MARK: Recent-form result badges (W/D/L)
    static let dsResultWin = Color(red: 48/255, green: 209/255, blue: 88/255, opacity: 0.85)
    static let dsResultDraw = Color(hex: "#636366")
    static let dsResultLoss = Color(red: 255/255, green: 69/255, blue: 58/255, opacity: 0.85)

    // MARK: Match Detail V2 — temporal-state accents
    static let dsStateKickoff = Color(hex: "#64D2FF")  // cyan — future
    static let dsStateLive = Color(hex: "#FF453A")     // red — live
    static let dsStateClock = Color(hex: "#FF9F0A")    // orange — live clock
    static let dsStateFinal = Color(hex: "#30D158")    // green — final

    // MARK: Match Detail V2 — surfaces
    static let dsMdPanel = Color(hex: "#14151C")       // header panel (navy)
    static let dsMdPanelBottom = Color(hex: "#101117") // header gradient end
    static let dsMdCard = Color(hex: "#1A1C23")         // info cards
    static let dsPitch = Color(hex: "#0E3B22")          // formation pitch green
    static let dsPitchBottom = Color(hex: "#0B321D")    // pitch gradient end
    static let dsPitchLine = Color(white: 1, opacity: 0.12)
}
