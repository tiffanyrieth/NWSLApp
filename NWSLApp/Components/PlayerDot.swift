//
//  PlayerDot.swift
//  NWSLApp
//
//  A player chip for Bracket Battle: a team-colored ring around the player's headshot
//  (jersey-number monogram fallback), with the player's name + team abbreviation
//  beneath. The voting/results matchup cards are built from two of these (A · VS · B).
//  The team ring is the caller's overlay (not part of the fill) so it frames the photo
//  and the monogram identically. The accent is resolved by the parent from ClubStore
//  (`Club.accentColor`) so it stays consistent with the rest of the app.
//

import SwiftUI

struct PlayerDot: View {
    let name: String
    let jersey: Int?
    let teamAbbreviation: String
    let accent: Color
    /// ESPN athlete id (the bracket Entrant's id) → resolves the headshot. Nil keeps the monogram.
    var athleteID: String? = nil
    var size: CGFloat = 44
    var showLabels: Bool = true

    var body: some View {
        VStack(spacing: 4) {
            PlayerHeadshot(athleteID: athleteID, size: size) {
                ZStack {
                    Circle().fill(Color.black.opacity(0.4))
                    Text(jersey.map(String.init) ?? "")
                        .font(.system(size: size * 0.32, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(accent)
                }
                .frame(width: size, height: size)
            }
            .overlay(Circle().strokeBorder(accent, lineWidth: 2))

            if showLabels {
                Text(name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(teamAbbreviation)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(Color.dsFgTertiary)
            }
        }
    }
}
