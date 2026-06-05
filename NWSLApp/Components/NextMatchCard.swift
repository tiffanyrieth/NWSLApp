//
//  NextMatchCard.swift
//  NWSLApp
//
//  Home → Module 1 ("Your next matches"): a followed team's next fixture as a
//  rich card. Distinct from MatchCard (the Schedule tab's compact row): this
//  one leads with a time-aware label ("TODAY" / "TOMORROW" / a date), shows
//  full team names, gives a live match an elevated treatment (pulsing-style red
//  dot + LIVE), and flips to the score + "FT" when a match has finished.
//
//  TEMP (data not mapped yet): the design spec also wants venue (pin icon) and
//  broadcast channel (TV icon) on this card. Those fields aren't decoded onto
//  Event yet — they ride the scoreboard response we already fetch
//  (competition.venue / broadcasts) and are tracked in CLAUDE.md What's-Next #5.
//  Add the third info line here once that decode lands.
//

import SwiftUI

struct NextMatchCard: View {
    let fixture: HomeViewModel.FollowedFixture

    private var event: Event { fixture.event }
    private var isLive: Bool { event.statusState == "in" }
    private var showScores: Bool { event.statusState == "in" || event.statusState == "post" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            VStack(alignment: .leading, spacing: 12) {
                teamRow(event.homeCompetitor)
                teamRow(event.awayCompetitor)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var header: some View {
        HStack(alignment: .center) {
            if isLive {
                HStack(spacing: 5) {
                    Circle()
                        .fill(.red)
                        .frame(width: 7, height: 7)
                    Text("LIVE")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.red)
                }
            } else {
                Text(fixture.label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(fixture.isResult ? Color.secondary : Color.accentColor)
            }
            Spacer(minLength: 8)
            Text(trailingStatus)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var trailingStatus: String {
        switch event.statusState {
        case "in":  return event.status?.displayClock ?? ""
        case "post": return event.status?.type?.shortDetail ?? "FT"
        default:    return kickoffTimeText
        }
    }

    @ViewBuilder
    private func teamRow(_ competitor: Competitor?) -> some View {
        HStack(spacing: 12) {
            TeamLogo(urlString: competitor?.team?.logo, size: 30)
            Text(teamName(competitor))
                .font(.body.weight(.medium))
                .lineLimit(1)
            Spacer(minLength: 8)
            if showScores, let score = competitor?.score {
                Text(score)
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
            }
        }
    }

    private func teamName(_ competitor: Competitor?) -> String {
        competitor?.team?.displayName
            ?? competitor?.team?.shortDisplayName
            ?? competitor?.team?.abbreviation
            ?? "—"
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
