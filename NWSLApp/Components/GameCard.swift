//
//  GameCard.swift
//  NWSLApp
//
//  A Fan Zone game card for Home's Module 3 (design handoff `UIComponents.jsx` →
//  `UIGameCard`): a 170×138 tile with the game's accent color world (trivia
//  indigo / bracket teal / predict pink), an emoji, a title, a status line, and an
//  optional corner badge (points/streak). Each game keeps its own color identity.
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
            HStack(spacing: 0) {
                Text(emoji).font(.system(size: 24))
                Spacer(minLength: 0)
                if let badge {
                    HStack(spacing: 3) {
                        if let badgeIcon { Text(badgeIcon).font(.system(size: 12)) }
                        Text(badge)
                            .font(.system(size: 12, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(accent)
                    }
                }
            }
            Spacer(minLength: 0)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.dsFgPrimary)
            Text(statusLine)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(completed ? Color.dsFgSecondary : accent)
                .padding(.top, 4)
        }
        .padding(DS.space8)
        .frame(width: DS.gameCardWidth, height: DS.gameCardHeight, alignment: .leading)
        .background(Color.dsBgCard)
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous)
                .stroke(accent.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous))
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
