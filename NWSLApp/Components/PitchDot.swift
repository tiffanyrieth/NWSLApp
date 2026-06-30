//
//  PitchDot.swift
//  NWSLApp
//
//  One player marker on a formation pitch: a team-colored disc with the player's
//  headshot (jersey-number monogram fallback), and the last name beneath. Shared by
//  FormationPitchView (single team) and CombinedPitchView (both teams).
//
//  The white ring is the caller's overlay (not part of the fill) so it frames the
//  photo and the monogram identically. See match-detail-v2-spec §7c/§8a.
//

import SwiftUI

struct PitchDot: View {
    let player: MatchPlayer
    let accent: ResolvedTeamColor

    var body: some View {
        VStack(spacing: 3) {
            PlayerHeadshot(athleteID: player.athlete?.id, size: 34) {
                ZStack {
                    Circle().fill(accent.fill)
                    Text(player.jersey ?? "")
                        .font(.caption.weight(.heavy))
                        .monospacedDigit()
                        .foregroundStyle(accent.onText)
                }
                .frame(width: 34, height: 34)
            }
            .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 1.5))
            Text(Self.lastName(player))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                // A single last name can't wrap, so shrink-to-fit rather than truncate
                // long ones (e.g. "Weatherholt"); the slightly wider frame holds them
                // without overlapping adjacent dots.
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .shadow(radius: 1)
        }
        .frame(width: 66)
    }

    /// A short, never-blank pitch label: a real last name (last word of whatever
    /// name field ESPN gives), else the jersey number, else a dash.
    static func lastName(_ player: MatchPlayer) -> String {
        let candidates = [player.athlete?.lastName, player.athlete?.shortName, player.athlete?.displayName]
        for name in candidates {
            if let word = name?.split(separator: " ").last, !word.isEmpty {
                return String(word)
            }
        }
        if let jersey = player.jersey, !jersey.isEmpty { return jersey }
        return "—"
    }
}
