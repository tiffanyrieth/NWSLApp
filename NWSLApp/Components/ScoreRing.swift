//
//  ScoreRing.swift
//  NWSLApp
//
//  The animated score ring shared by the two COMMUNITY-family games' result screens — Know Her Game and
//  NWSL Trivia — so a "4/5" reads identically in both (the Fan Zone v2 anti-drift goal: the community
//  games share components, they don't each re-roll their own). Takes the game's accent so it keeps each
//  game's identity (amber for Know Her, indigo for Trivia). Pure/presentational — no state.
//

import SwiftUI

struct ScoreRing: View {
    let score: Int
    let total: Int
    let accent: Color
    var size: CGFloat = 132

    private var fraction: CGFloat { total > 0 ? CGFloat(score) / CGFloat(total) : 0 }

    var body: some View {
        ZStack {
            Circle().stroke(accent.opacity(0.18), lineWidth: 10)
                .frame(width: size, height: size)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: size, height: size)
            VStack(spacing: 2) {
                Text("\(score)/\(total)")
                    .dsFont(34, weight: .heavy, design: .rounded).foregroundStyle(accent)
                Text("correct").dsFont(12).foregroundStyle(.secondary)
            }
        }
    }
}
