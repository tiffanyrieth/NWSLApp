//
//  FeaturedGameCard.swift
//  NWSLApp
//
//  The Fan Zone "featured" lead card (facelift) — a wide tile that anchors Home's
//  Module 3 game row so the section reads as prominent, not a runt. It leads the
//  horizontal row (sized to ~85% of the width via the caller's containerRelativeFrame),
//  followed by the remaining games as standard `GameCard` tiles. The featured game is
//  the most time-sensitive one (HomeView picks it).
//
//  Composition: a glowing emoji medallion on the left, then a column with a FEATURED
//  eyebrow + optional points/streak badge, the game title, a one-line tagline, and a
//  solid-accent CTA pill (stronger than the tile's tinted pill). Same accent-glow +
//  card-fill world as `GameCard`, just larger and richer.
//

import SwiftUI

struct FeaturedGameCard: View {
    let emoji: String
    let title: String
    /// The action/state line shown in the CTA pill (e.g. "Predict now", "120 pts").
    let statusLine: String
    /// A one-line descriptor of the game ("Pick your team's XI before kickoff").
    let tagline: String
    /// The game's identity color (Color.dsGameTrivia / dsGameBracket / dsGamePredict).
    let accent: Color
    var badge: String? = nil
    var badgeIcon: String? = nil
    /// When true the CTA dims to a neutral "done" state (no arrow).
    var completed: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            medallion
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("FEATURED")
                        .dsFont(10, weight: .bold)
                        .tracking(1.4)
                        .foregroundStyle(accent)
                    Spacer(minLength: 8)
                    if let badge {
                        HStack(spacing: 3) {
                            if let badgeIcon { Text(badgeIcon).dsFont(12) }
                            Text(badge)
                                .dsFont(13, weight: .bold, monospacedDigit: true)
                                .foregroundStyle(accent)
                        }
                    }
                }
                Text(title)
                    .dsFont(20, weight: .bold)
                    .foregroundStyle(Color.dsFgPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 3)
                Text(tagline)
                    .dsFont(12.5)
                    .foregroundStyle(Color.dsFgSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 3)
                Spacer(minLength: 10)
                statusPill
            }
        }
        .padding(16)
        .frame(height: DS.gameCardHeight, alignment: .top)
        .frame(maxWidth: .infinity)
        .background(
            RadialGradient(
                colors: [accent.opacity(0.28), .clear],
                center: UnitPoint(x: 0.96, y: 0.0), startRadius: 6, endRadius: 340
            )
        )
        .background(Color.dsBgCard)
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous)
                .stroke(accent.opacity(0.5), lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous))
    }

    private var medallion: some View {
        ZStack {
            Circle().fill(accent.opacity(0.18))
            Circle().stroke(accent.opacity(0.4), lineWidth: 1)
            Text(emoji).dsFont(34)
        }
        .frame(width: 64, height: 64)
    }

    // Solid-accent CTA pill (white label) — louder than the tile's tinted pill.
    private var statusPill: some View {
        Text(completed ? statusLine : "\(statusLine) →")
            .dsFont(13, weight: .bold)
            .foregroundStyle(completed ? Color.dsFgSecondary : .white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                completed ? AnyShapeStyle(Color.dsBgTertiary) : AnyShapeStyle(accent),
                in: Capsule()
            )
    }
}

#Preview {
    ScrollView(.horizontal) {
        HStack(spacing: 12) {
            FeaturedGameCard(
                emoji: "⚽", title: "Predict the XI", statusLine: "Predict now",
                tagline: "Pick your team's XI before kickoff", accent: .dsGamePredict
            )
            .containerRelativeFrame(.horizontal, count: 100, span: 85, spacing: 12)
            GameCard(emoji: "🏆", title: "Bracket Battle", statusLine: "Round 2 of 4", accent: .dsGameBracket, badge: "120", badgeIcon: "🏆")
        }
        .padding(.horizontal, 16)
    }
    .background(Color.dsBgGrouped)
}
