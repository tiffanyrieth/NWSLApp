//
//  PlayerSpotlightCard.swift
//  NWSLApp
//
//  Home's Module 2 ("Get to know your players") card — design-handoff refresh
//  (`HomeScreen.jsx`). A compact, equal-weight profile card shown one-per-followed
//  team in a horizontal carousel: a 3px team-color accent line, a "PLAYER OF THE
//  WEEK" eyebrow, the jersey-number badge, name + "position · ABBR", the 2-3
//  sentence hook (the sell), a Goals/Assists/Apps stat strip, and a "Read
//  spotlight →" CTA. The video moved to the detail page (PlayerSpotlightView) —
//  this card is the teaser, wrapped in a NavigationLink by HomeView.
//
//  Team color: the jersey badge uses the club's brand fill + a legible on-color
//  (Color.teamAccent); the eyebrow, abbreviation, first stat, and CTA use the
//  club's dark-legible accent (Club.accentColor). Falls back to the app accent
//  when the club isn't resolved.
//

import SwiftUI

struct PlayerSpotlightCard: View {
    let spotlight: PlayerSpotlight
    /// Resolved from the followed Club directory by abbreviation (crest + colors).
    let club: Club?

    /// Dark-legible team accent for the eyebrow / abbr / CTA / first stat.
    private var accent: Color { club?.accentColor ?? .dsAccent }
    /// Team-brand fill + on-color for the jersey badge.
    private var jersey: (fill: Color, on: Color) { Color.teamAccent(hex: club?.brandHex) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(accent).frame(height: 3)   // team-color accent line
            VStack(alignment: .leading, spacing: 12) {
                Text("Player of the week")
                    .trackedCaps(size: 10, tracking: 1.5, color: accent)
                header
                Text(spotlight.bioBlurb)
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .foregroundStyle(Color.dsFgSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                statStrip
                readCTA
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsBgCard)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous))
    }

    // MARK: - Header (jersey badge + name + position · ABBR)

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(jersey.fill)
                Text("\(spotlight.jerseyNumber)")
                    .font(.system(size: 18, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(jersey.on)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(spotlight.playerName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.dsFgPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(spotlight.position)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.dsFgSecondary)
                    Circle().fill(Color.dsFgQuaternary).frame(width: 3, height: 3)
                    Text(spotlight.teamAbbreviation)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accent)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Stat strip (Goals / Assists / Apps)

    private var statStrip: some View {
        let s = spotlight.demoSeasonStats
        return HStack(spacing: 0) {
            statCell("\(s.goals)", "Goals", highlight: true)
            statDivider
            statCell("\(s.assists)", "Assists")
            statDivider
            statCell("\(s.apps)", "Apps")
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color.dsBgTertiary)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusSm, style: .continuous))
    }

    private func statCell(_ value: String, _ label: String, highlight: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(highlight ? accent : Color.dsFgPrimary)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.dsFgTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle().fill(Color.dsSeparator).frame(width: 1, height: 24)
    }

    private var readCTA: some View {
        HStack(spacing: 6) {
            Text("Read spotlight").font(.system(size: 13, weight: .semibold))
            Text("→").font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(accent)
        .frame(maxWidth: .infinity)
    }
}
