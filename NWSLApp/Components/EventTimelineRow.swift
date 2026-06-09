//
//  EventTimelineRow.swift
//  NWSLApp
//
//  One entry in a match's events timeline: a minute badge, a type icon (goal /
//  card / substitution), and the player(s) involved. Built from a summary
//  `KeyEvent` (see MatchSummary.swift); the row maps ESPN's `type.type` to an SF
//  Symbol + tint and pulls names from `participants` — for a goal that's scorer
//  (+ assist), for a card the booked player, for a sub the two players swapped.
//
//  Defensive throughout: a missing minute, unknown type, or empty participants
//  still renders a sensible row rather than blank space.
//

import SwiftUI

struct EventTimelineRow: View {
    let event: KeyEvent
    /// The match's two team ids + abbreviations, so the row can label which side
    /// the event belongs to (KeyEvent.team carries an id + name, not an abbr).
    var homeTeamID: String? = nil
    var awayTeamID: String? = nil
    var homeAbbr: String? = nil
    var awayAbbr: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(minute)
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)

            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(iconColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(primaryName)
                    .font(.subheadline.weight(.semibold))
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            if let abbr = teamAbbreviation {
                Text(abbr)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
    }

    private var teamAbbreviation: String? {
        guard let id = event.team?.id else { return nil }
        if id == homeTeamID { return homeAbbr }
        if id == awayTeamID { return awayAbbr }
        return nil
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

    /// The second line: assist for a goal, the outgoing player for a sub.
    private var detail: String? {
        let type = event.type?.type ?? ""
        guard names.count > 1 else {
            // No second participant — show the event label for context on cards.
            return type.contains("card") ? event.type?.text : nil
        }
        if type == "goal" {
            return "Assist: \(names[1])"
        }
        if type.contains("substitution") {
            return "↓ \(names[1])"
        }
        return names.dropFirst().joined(separator: ", ")
    }

    private var icon: String {
        switch event.type?.type ?? "" {
        case let t where t.contains("goal"):         return "soccerball"
        case let t where t.contains("yellow"):       return "rectangle.portrait.fill"
        case let t where t.contains("red"):          return "rectangle.portrait.fill"
        case let t where t.contains("substitution"): return "arrow.left.arrow.right"
        default:                                      return "circle.fill"
        }
    }

    private var iconColor: Color {
        switch event.type?.type ?? "" {
        case let t where t.contains("yellow"): return .yellow
        case let t where t.contains("red"):    return .red
        case let t where t.contains("goal"):   return .primary
        default:                                return .secondary
        }
    }
}

#Preview {
    VStack(alignment: .leading) {
        EventTimelineRow(event: KeyEvent(
            id: "1",
            type: KeyEventType(id: "70", text: "Goal", type: "goal"),
            clock: KeyEventClock(value: 3064, displayValue: "52'"),
            scoringPlay: true,
            team: nil,
            participants: [
                KeyEventParticipant(athlete: MatchAthlete(id: "1", displayName: "Olivia Moultrie", shortName: nil, lastName: nil)),
                KeyEventParticipant(athlete: MatchAthlete(id: "2", displayName: "Pietra Tordin", shortName: nil, lastName: nil)),
            ]
        ))
    }
    .padding()
}
