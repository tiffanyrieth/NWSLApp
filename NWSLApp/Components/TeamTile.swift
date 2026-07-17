//
//  TeamTile.swift
//  NWSLApp
//
//  The shared visual treatment for a club tile, used by BOTH the Teams tab grid and the
//  onboarding club picker so the two can't drift (design-audit dedup). Two pieces:
//
//   • `TeamCrestGlow` — a ring-free crest (bare, like a real logo) with a soft team-color
//     halo behind it (a blurred color, NOT a drop shadow — respects the no-shadow rule).
//   • `.teamTileSurface(...)` — the card surface: dsBgCard, blooming a team-color radial
//     wash + gaining a soft club-color border once the club is followed.
//
//  The two screens differ ONLY in what sits inside the card (Teams: a Follow/Following pill
//  + bell for a browse context; onboarding: tap-to-select + a check + bell for rapid first-
//  run picking) — the surface + crest treatment is identical and lives here.
//

import SwiftUI

struct TeamCrestGlow: View {
    let club: Club
    var size: CGFloat = 58

    var body: some View {
        TeamLogo(urlString: club.logoURL, teamAbbreviation: club.abbreviation, size: size)
            .background(
                Circle()
                    .fill(club.accentColor.opacity(0.22))
                    .blur(radius: 14)
            )
    }
}

extension View {
    /// The club-tile card surface: dsBgCard base, a team-color radial wash blooming from
    /// behind the crest + a soft club-color border once followed, clipped to `cornerRadius`.
    func teamTileSurface(club: Club, isFollowing: Bool, cornerRadius: CGFloat = DS.radiusXl) -> some View {
        self
            .background(
                ZStack {
                    Color.dsBgCard
                    if isFollowing {
                        RadialGradient(
                            colors: [club.accentColor.opacity(0.17), .clear],
                            center: UnitPoint(x: 0.5, y: 0.32),
                            startRadius: 0, endRadius: 115
                        )
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(isFollowing ? club.accentColor.opacity(0.4) : .clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
