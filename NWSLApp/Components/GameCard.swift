//
//  GameCard.swift
//  NWSLApp
//
//  A Fan Zone game card for Home's Module 3 (facelift, design handoff `home.jsx` →
//  `GameCard`): a 200×160 tile with the game's accent color world (trivia indigo /
//  bracket teal / predict pink) — a radial accent glow in the top-right corner, an
//  emoji, an optional corner badge (points/streak), the title, and the status as a
//  filled accent pill ("Play now →"). Each game keeps its own color identity.
//

import SwiftUI

struct GameCard: View {
    let emoji: String
    let title: String
    let statusLine: String
    /// The game's identity color (Color.dsGameTrivia / dsGameBracket / dsGamePredict).
    let accent: Color
    /// When true the status line dims to secondary (e.g. "Done today ✓").
    var completed: Bool = false
    /// Optional corner badge value (e.g. "45" points) + its leading emoji.
    var badge: String? = nil
    var badgeIcon: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                Text(emoji).dsFont(30)
                Spacer(minLength: 0)
                if let badge {
                    HStack(spacing: 3) {
                        if let badgeIcon { Text(badgeIcon).dsFont(12) }
                        Text(badge)
                            .dsFont(13, weight: .bold, monospacedDigit: true)
                            .foregroundStyle(accent)
                    }
                }
            }
            Spacer(minLength: 0)
            Text(title)
                .dsFont(17, weight: .bold)
                .foregroundStyle(Color.dsFgPrimary)
                // Fixed 200pt tile: scale the title down rather than truncate ("Bracket Bat…")
                // at large text.
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            statusPill
                .padding(.top, 8)
        }
        .padding(16)
        .frame(width: DS.gameCardWidth, height: DS.gameCardHeight, alignment: .leading)
        // Accent glow in the top-right corner over the card fill (home.jsx
        // `radial-gradient(circle at 88% 8%, accent33, transparent)`).
        .background(
            RadialGradient(
                colors: [accent.opacity(0.22), .clear],
                center: UnitPoint(x: 0.88, y: 0.08), startRadius: 4, endRadius: 170
            )
        )
        .background(Color.dsBgCard)
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous)
                .stroke(accent.opacity(0.4), lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous))
    }

    // Status as a filled accent pill ("Play now →"); dims to a neutral pill when
    // the game's done for the day (no arrow on a completed state).
    private var statusPill: some View {
        Text(completed ? statusLine : "\(statusLine) →")
            .dsFont(12.5, weight: .bold)
            .foregroundStyle(completed ? Color.dsFgSecondary : accent)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(
                (completed ? Color.dsFgSecondary : accent).opacity(0.16),
                in: Capsule()
            )
    }
}

#Preview {
    HStack(spacing: 12) {
        GameCard(emoji: "⚽", title: "Predict the XI", statusLine: "Predict now", accent: .dsGamePredict)
        GameCard(emoji: "🏆", title: "Bracket Battle", statusLine: "Round 2 of 4", accent: .dsGameBracket, badge: "45", badgeIcon: "🏆")
        GameCard(emoji: "🧠", title: "Daily Trivia", statusLine: "Done today ✓", accent: .dsGameTrivia, completed: true, badge: "3", badgeIcon: "🔥")
    }
    .padding()
    .background(Color.dsBgGrouped)
}
