//
//  ScoreRing.swift
//  NWSLApp
//
//  The score ring shared across the Fan Zone result screens, so an "N of M" reads identically
//  everywhere (the Fan Zone v2 anti-drift goal: games share components, they don't each re-roll
//  their own). Takes the game's accent so it keeps each game's identity — amber for Know Her,
//  indigo for Trivia, teal for The Bracket, pink for Predict.
//
//  Generalized 2026-07-28 for Predict the XI's results redesign. Predict's hero is "8 / of 11
//  starters called", not "8/11 correct", and its ring animates on reveal — so the CENTER is now a
//  caller-supplied view and animation is opt-in. The original `init(score:total:accent:size:)` is
//  preserved exactly, defaulting to the "N/M · correct" label and no animation, so Know Her, Trivia
//  and The Bracket render byte-identically and needed no edit.
//
//  Pure/presentational — no state beyond the reveal animation's own.
//

import SwiftUI

struct ScoreRing<Center: View>: View {
    /// 0…1. Passed explicitly rather than derived, so a caller whose hero isn't a simple
    /// score-over-total (a season average out of the per-match max, say) doesn't have to fake one.
    let fraction: CGFloat
    let accent: Color
    var size: CGFloat = 132
    var lineWidth: CGFloat = 10
    /// Sweep the arc in on appear. Off by default — the existing three games render the ring at
    /// rest, and turning it on for them would be an unrequested change to shipped screens.
    var animated: Bool = false
    @ViewBuilder var center: () -> Center

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: CGFloat = 0

    private var target: CGFloat { max(0, min(1, fraction)) }

    var body: some View {
        ZStack {
            Circle().stroke(accent.opacity(0.18), lineWidth: lineWidth)
                .frame(width: size, height: size)
            Circle()
                .trim(from: 0, to: animated ? shown : target)
                .stroke(accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: size, height: size)
            center()
        }
        .task(id: target) {
            guard animated else { return }
            // Reduce Motion gets the final value with no sweep — the number is the information;
            // the animation is decoration.
            guard !reduceMotion else { shown = target; return }
            shown = 0
            withAnimation(.easeOut(duration: 0.9)) { shown = target }
        }
    }
}

/// The original center label: a big "N/M" over the word "correct".
struct ScoreRingDefaultLabel: View {
    let score: Int
    let total: Int
    let accent: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(score)/\(total)")
                .dsFont(34, weight: .heavy, design: .rounded).foregroundStyle(accent)
            Text("correct").dsFont(12).foregroundStyle(Color.dsFgSecondary)
        }
    }
}

extension ScoreRing where Center == ScoreRingDefaultLabel {
    /// The shipped call shape — unchanged for Know Her Game, NWSL Trivia and The Bracket.
    init(score: Int, total: Int, accent: Color, size: CGFloat = 132) {
        self.init(fraction: total > 0 ? CGFloat(score) / CGFloat(total) : 0,
                  accent: accent,
                  size: size,
                  animated: false) {
            ScoreRingDefaultLabel(score: score, total: total, accent: accent)
        }
    }
}
