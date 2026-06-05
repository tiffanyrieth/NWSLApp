//
//  PlayerSpotlightCard.swift
//  NWSLApp
//
//  Home's Module 2 ("Get to know your players") — a compact "Player of the week"
//  card (per Reference/Design/home-tab-design-spec.md). One player from a followed
//  team, rotated weekly, introducing the roster one person at a time. Shows a
//  jersey-number badge, the player's name, "Position · Team", and a "Watch
//  spotlight" link to team content.
//
//  TEMP (no team-color in the Club directory): the jersey badge uses the app
//  accent color. ESPN's roster payload carries each club's hex, but Home doesn't
//  fetch rosters — when a shared color source exists, pass the hex into
//  Color.teamAccent here for a true team-colored badge.
//

import SwiftUI

struct PlayerSpotlightCard: View {
    let spotlight: PlayerSpotlight
    /// Resolved from the followed Club directory by abbreviation (crest + name).
    let club: Club?
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let url = spotlight.watchURL { openURL(url) }
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                Text("Player of the week")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                HStack(spacing: 14) {
                    jerseyBadge
                    VStack(alignment: .leading, spacing: 3) {
                        Text(spotlight.playerName)
                            .font(.title3.weight(.bold))
                            .lineLimit(1)
                        Text("\(spotlight.position) · \(teamName)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 4) {
                    Image(systemName: "play.circle.fill")
                    Text("Watch spotlight")
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
                .foregroundStyle(Color.accentColor)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var jerseyBadge: some View {
        let accent = Color.teamAccent(hex: nil)   // TEMP: no Club hex — app accent
        return ZStack {
            Circle().fill(accent.fill)
            Text("\(spotlight.jerseyNumber)")
                .font(.title2.weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(accent.on)
        }
        .frame(width: 52, height: 52)
    }

    private var teamName: String {
        club?.shortName ?? club?.displayName ?? spotlight.teamAbbreviation
    }
}
