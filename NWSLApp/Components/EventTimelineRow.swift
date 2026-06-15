//
//  EventTimelineRow.swift
//  NWSLApp
//
//  One entry in a match's Play-by-Play (design handoff `match-detail.jsx` →
//  `EventRow`): minute · a team-color crest box on the LEFT (scan-by-color, no
//  need to read to the far right) · the event glyph (goal / card / substitution)
//  · the player + detail · and, for a goal, the running scoreline on the right. A
//  goal row gets a team-color wash fading right so big moments stand out.
//
//  The team identity (color + crest) and the running scoreline are resolved by the
//  caller (MatchDetailView) and passed in.
//

import SwiftUI

struct EventTimelineRow: View {
    let event: KeyEvent
    /// Minute-marker tint — the match's temporal-state accent (cyan past/future,
    /// orange live).
    var minuteColor: Color = .secondary
    /// The event team's resolved color (left crest box + goal wash).
    var teamColor: Color = .dsFgSecondary
    /// The event team's crest (real art via TeamLogo) for the left box.
    var crestURL: String? = nil
    var crestAbbr: String? = nil
    /// Running scoreline on a goal row, e.g. "1–0".
    var score: String? = nil

    private var isGoal: Bool { (event.type?.type ?? "").contains("goal") }

    var body: some View {
        HStack(spacing: 11) {
            Text(minute)
                .font(.system(size: 13, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(minuteColor)
                .frame(width: 30, alignment: .center)

            // Team identity on the LEFT — a color-tinted box holding the real crest.
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(teamColor.opacity(0.16))
                TeamLogo(urlString: crestURL, teamAbbreviation: crestAbbr, size: 20)
            }
            .frame(width: 30, height: 30)

            iconView.frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(primaryName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.dsFgPrimary)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.dsFgSecondary)
                }
            }

            Spacer(minLength: 0)

            if isGoal, let score {
                Text(score)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.dsFgPrimary)
            }
        }
        .padding(.vertical, 10)
        .padding(.leading, 2)
        .padding(.trailing, 8)
        // Goals get a team-color wash fading right — scan the timeline by color.
        .background {
            if isGoal {
                LinearGradient(
                    stops: [
                        .init(color: teamColor.opacity(0.20), location: 0),
                        .init(color: teamColor.opacity(0), location: 0.72),
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    // A substitution gets the green-in / red-out arrows; a card is a small colored
    // rectangle; a goal is a soccer ball.
    @ViewBuilder
    private var iconView: some View {
        let type = event.type?.type ?? ""
        if type.contains("substitution") {
            SubstitutionArrows()
        } else if type.contains("yellow") {
            cardRect(.dsWarning)
        } else if type.contains("red") {
            cardRect(.dsLive)
        } else if type.contains("goal") {
            Image(systemName: "soccerball.inverse")
                .font(.system(size: 15))
                .foregroundStyle(Color.dsFgPrimary)
        } else {
            Image(systemName: "circle.fill")
                .font(.system(size: 7))
                .foregroundStyle(.secondary)
        }
    }

    private func cardRect(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(color)
            .frame(width: 10, height: 13)
    }

    // MARK: - Derived display

    private var minute: String {
        let clock = event.clock?.displayValue ?? ""
        return clock.isEmpty ? "—" : clock
    }

    private var names: [String] {
        (event.participants ?? []).compactMap { $0.athlete?.displayName }
    }

    private var primaryName: String {
        names.first ?? event.type?.text ?? "—"
    }

    /// Assist for a goal, "on for {outgoing}" for a sub (ESPN lists [in, out]).
    private var detail: String? {
        let type = event.type?.type ?? ""
        guard names.count > 1 else {
            return type.contains("card") ? event.type?.text : nil
        }
        if type == "goal" {
            return "Assist: \(names[1])"
        }
        if type.contains("substitution") {
            return "on for \(names[1])"
        }
        return names.dropFirst().joined(separator: ", ")
    }
}

/// The standard substitution marker: a green up-arrow (coming on) beside a red
/// down-arrow (going off).
private struct SubstitutionArrows: View {
    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "arrow.up").foregroundStyle(Color.dsSuccess)
            Image(systemName: "arrow.down").foregroundStyle(Color.dsError)
        }
        .font(.system(size: 11, weight: .bold))
    }
}
