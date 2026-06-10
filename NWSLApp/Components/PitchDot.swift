//
//  PitchDot.swift
//  NWSLApp
//
//  One player marker on a formation pitch: a team-colored disc with the jersey
//  number, and the player's last name beneath. Shared by FormationPitchView
//  (single team) and CombinedPitchView (both teams).
//
//  TEMP (headshots): the disc is a jersey-number monogram for now — a follow-up
//  swaps the fill for a real headshot photo (the frame + monogram stay as the
//  fallback). See match-detail-v2-spec §7c/§8a.
//

import SwiftUI

struct PitchDot: View {
    let player: MatchPlayer
    let accent: ResolvedTeamColor

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle().fill(accent.fill)
                Circle().stroke(.white.opacity(0.7), lineWidth: 1.5)
                Text(player.jersey ?? "")
                    .font(.caption.weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(accent.onText)
            }
            .frame(width: 34, height: 34)
            Text(Self.lastName(player))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .shadow(radius: 1)
        }
        .frame(width: 60)
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
