//
//  PlayerCard.swift
//  NWSLApp
//
//  One player as a card in the Teams → Squad grid (the "meet the team" view):
//  a team-color top accent, the jersey number in a team-color circle badge, the
//  player's short name, and their position. Replaces the old list-row PlayerRow
//  now that the squad is a 2-column grid (see the Teams tab design spec).
//
//  No photo, by design: ESPN's NWSL feed returns null headshots, so the badge
//  shows the jersey number (or initials when a number is missing) — the same
//  neutral-monogram spirit as TeamLogo. The team color comes from the roster
//  payload via Color.teamAccent, which also picks a legible number color.
//

import SwiftUI

struct PlayerCard: View {
    let athlete: Athlete
    /// The club's ESPN color hex; nil falls back to the app accent.
    let accentHex: String?

    var body: some View {
        let accent = Color.teamAccent(hex: accentHex)
        VStack(spacing: 0) {
            // Team-color top accent (3px), per spec.
            Rectangle()
                .fill(accent.fill)
                .frame(height: 3)

            VStack(spacing: 8) {
                ZStack {
                    Circle().fill(accent.fill)
                    Text(badgeLabel)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(accent.on)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .padding(6)
                }
                .frame(width: 48, height: 48)

                Text(athlete.shortName ?? athlete.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.dsFgPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if let position = athlete.positionName {
                    Text(position)
                        .font(.caption)
                        .foregroundStyle(Color.dsFgSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
        }
        .background(Color.dsBgCard)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusMd))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusMd)
                .stroke(Color.dsSeparator.opacity(0.6), lineWidth: 0.5)
        )
    }

    // Jersey number when present, otherwise the player's initials.
    private var badgeLabel: String {
        if let jersey = athlete.jersey, !jersey.isEmpty { return jersey }
        let initials = athlete.name
            .split(separator: " ")
            .compactMap { $0.first }
            .prefix(2)
            .map(String.init)
            .joined()
        return initials.isEmpty ? "—" : initials
    }
}

#Preview {
    let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    LazyVGrid(columns: columns, spacing: 12) {
        PlayerCard(athlete: Athlete(
            id: "1", name: "Trinity Rodman", shortName: "T. Rodman", jersey: "2",
            positionName: "Forward", positionAbbreviation: "F",
            age: 23, displayHeight: "5' 8\"", citizenship: "USA"
        ), accentHex: "C8102E")
        PlayerCard(athlete: Athlete(
            id: "2", name: "Aubrey Kingsbury", shortName: "A. Kingsbury", jersey: nil,
            positionName: "Goalkeeper", positionAbbreviation: "G",
            age: 33, displayHeight: nil, citizenship: "USA"
        ), accentHex: nil)
    }
    .padding()
}
