//
//  TeamColorWash.swift
//  NWSLApp
//
//  The shared team-color wash — the sanctioned way to tint a card with club identity. Extracted so
//  Schedule (`MatchCard`), Predict the XI fixture/leaderboard cards, and any future surface draw the
//  SAME gradient recipe instead of hand-rolling it (before this, MatchCard and MatchDetail each rolled
//  their own). Two modes:
//
//   • TWO-TEAM (`away` non-nil) — home color bleeds from the left @0.18, away from the right @0.18, clear
//     through the middle, ~100° tilt. The exact recipe MatchCard shipped, so a migration is pixel-identical.
//   • SINGLE-TEAM (`away == nil`) — a light leading tint (`home @0.12 → clear`) for one-club cards.
//
//  Colors are passed in ALREADY RESOLVED (the caller calls `Color.teamColor(for:liftOnDark:)`), so this
//  view stays presentation-only and never hardcodes a hex (fan-zone rule). Layer it OVER the surface's
//  family token via the `base` parameter (Schedule = `dsBgCard`, Predict = `dsMdCard`) so the
//  Competitive-vs-Community family read is preserved.
//

import SwiftUI

struct TeamWashBackground: View {
    /// The card's family base color, drawn under the wash (e.g. `.dsBgCard` / `.dsMdCard`).
    let base: Color
    /// Home / primary team color, already resolved for the surface's brightness.
    let home: Color
    /// Away team color for a two-team card; `nil` for a single-team card (→ leading tint only).
    var away: Color? = nil

    var body: some View {
        ZStack {
            base
            if let away {
                // Two-team: home left @0.18, away right @0.18, clear center, ~100° (horizontal, tilted).
                LinearGradient(
                    stops: [
                        .init(color: home.opacity(0.18), location: 0.0),
                        .init(color: home.opacity(0.0), location: 0.34),
                        .init(color: away.opacity(0.0), location: 0.66),
                        .init(color: away.opacity(0.18), location: 1.0),
                    ],
                    startPoint: UnitPoint(x: 0, y: 0.42),
                    endPoint: UnitPoint(x: 1, y: 0.58)
                )
            } else {
                // Single-team: a quiet leading tint that fades out by the card's midpoint.
                LinearGradient(
                    stops: [
                        .init(color: home.opacity(0.12), location: 0.0),
                        .init(color: home.opacity(0.0), location: 0.5),
                    ],
                    startPoint: UnitPoint(x: 0, y: 0.5),
                    endPoint: UnitPoint(x: 1, y: 0.5)
                )
            }
        }
    }
}
