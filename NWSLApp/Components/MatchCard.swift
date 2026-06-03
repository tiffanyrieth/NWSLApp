//
//  MatchCard.swift
//  NWSLApp
//
//  One game as a self-contained card in ScheduleView (MLS-app style). Left:
//  stacked home/away rows, each a team crest + abbreviation, with scores once
//  the match is in progress or final. Right: status badge — kickoff time for
//  upcoming matches, "LIVE" + clock for in-progress, or the short status
//  detail ("FT") for finished matches.
//
//  Honors design rule #1: lives entirely inside its card, no overlays.
//  Clarity over density: a solid rounded card surface with breathing room so
//  ~4–5 games read cleanly per screen.
//

import SwiftUI

struct MatchCard: View {
    let event: Event

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 18) {
                teamRow(event.homeCompetitor)
                teamRow(event.awayCompetitor)
            }
            Spacer(minLength: 8)
            statusView
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func teamRow(_ competitor: Competitor?) -> some View {
        HStack(spacing: 12) {
            TeamLogo(urlString: competitor?.team?.logo, size: 34)
            // Fixed minWidth keeps home/away abbreviations aligned regardless
            // of logo load state — no horizontal shift as crests resolve.
            Text(competitor?.team?.abbreviation ?? competitor?.team?.shortDisplayName ?? "—")
                .font(.title3.weight(.medium))
                .frame(minWidth: 52, alignment: .leading)
            if showScores, let score = competitor?.score {
                Text(score)
                    .font(.title3.weight(.bold))
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
