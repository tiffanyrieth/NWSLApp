//
//  PlayerDot.swift
//  NWSLApp
//
//  A player chip for Bracket Battle: a team-colored ring around the jersey number,
//  with the player's name + team abbreviation beneath. The voting/results matchup
//  cards are built from two of these (A · VS · B). Like PitchDot it's a jersey
//  monogram, not a headshot — the permanent no-NWSL-headshots reality (the team
//  ring carries the identity instead). The accent is resolved by the parent from
//  ClubStore (`Club.accentColor`) so it stays consistent with the rest of the app.
//

import SwiftUI

struct PlayerDot: View {
    let name: String
    let jersey: Int?
    let teamAbbreviation: String
    let accent: Color
    var size: CGFloat = 44
    var showLabels: Bool = true

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().fill(Color.black.opacity(0.4))
                Circle().strokeBorder(accent, lineWidth: 2)
                Text(jersey.map(String.init) ?? "")
                    .font(.system(size: size * 0.32, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(accent)
            }
            .frame(width: size, height: size)

            if showLabels {
                Text(name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(teamAbbreviation)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(Color.dsFgTertiary)
            }
        }
    }
}
