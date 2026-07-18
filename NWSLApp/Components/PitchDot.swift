//
//  PitchDot.swift
//  NWSLApp
//
//  One player marker on a formation pitch: a team-colored disc with the player's
//  headshot (jersey-number monogram fallback), and the jersey number + last name
//  beneath ("25 Farmer" — the NWSL lineup style, so the number stays visible even when
//  a headshot IS shown; the disc alone dropped it). Shared by FormationPitchView
//  (single team) and CombinedPitchView (both teams).
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
            Text(Self.pitchLabel(player))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                // A number + single last name can't wrap, so shrink-to-fit rather than
                // truncate long ones (e.g. "25 Weatherholt"); the slightly wider frame
                // holds them without overlapping adjacent dots.
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .shadow(radius: 1)
        }
        .frame(width: 66)
    }

    /// The pitch label: jersey number + short last name ("25 Farmer"), matching the NWSL
    /// lineup so the number is visible whether or not a headshot loads. Degrades cleanly:
    /// no number → just the name; no name → just the number (never "25 25"); neither → "—".
    static func pitchLabel(_ player: MatchPlayer) -> String {
        let name = lastName(player)
        guard let jersey = player.jersey, !jersey.isEmpty else { return name }
        return name == jersey ? jersey : "\(jersey) \(name)"
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
