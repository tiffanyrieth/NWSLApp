//
//  MatchCard.swift
//  NWSLApp
//
//  One row in ScheduleView's list. Left: stacked home/away team rows with
//  scores (or blank if the match hasn't been played). Right: status badge —
//  kickoff time for upcoming matches, "LIVE" + clock for in-progress, or the
//  short status detail ("FT") for finished matches.
//
//  Honors design rule #1: lives entirely inside its list row, no overlays.
//

import SwiftUI

struct MatchCard: View {
    let event: Event

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                teamRow(event.homeCompetitor)
                teamRow(event.awayCompetitor)
            }
            Spacer(minLength: 8)
            statusView
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func teamRow(_ competitor: Competitor?) -> some View {
        HStack(spacing: 8) {
            Text(competitor?.team?.abbreviation ?? competitor?.team?.shortDisplayName ?? "—")
                .font(.body.monospaced())
                .frame(minWidth: 44, alignment: .leading)
            if showScores, let score = competitor?.score {
                Text(score)
                    .font(.body.weight(.semibold))
            }
        }
    }

    private var showScores: Bool {
        event.statusState == "in" || event.statusState == "post"
    }

    @ViewBuilder
    private var statusView: some View {
        switch event.statusState {
        case "in":
            VStack(alignment: .trailing, spacing: 2) {
                Text("LIVE")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.red)
                if let clock = event.status?.displayClock {
                    Text(clock)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        case "post":
            Text(event.status?.type?.shortDetail ?? "FT")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        default:
            Text(kickoffTimeText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var kickoffTimeText: String {
        guard let kickoff = event.kickoff else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: kickoff)
    }
}
