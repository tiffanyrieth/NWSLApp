//
//  ComingUpRow.swift
//  NWSLApp
//
//  Home's Module 4 ("Coming up") — a COMPACT schedule row, one per followed team
//  (Reference/Design/home-tab-design-spec.md + the design-handoff refresh): mini
//  home-v-away crests (bare logos), the matchup as team-colored abbreviations
//  ("WAS vs POR"), and a time-aware line ("Tomorrow · 7:30 PM"), with a live
//  indicator or a compact result line when relevant. The full detail lives in the
//  Schedule tab.
//
//  Reuses HomeViewModel.FollowedFixture so Module 4 is a lighter rendering of data
//  Home already has — no extra fetch. Team colors come from the shared ClubStore
//  (scoreboard competitors carry none), resolved distinct + dark-legible.
//

import SwiftUI

struct ComingUpRow: View {
    let fixture: HomeViewModel.FollowedFixture
    @Environment(ClubStore.self) private var clubStore

    private var event: Event { fixture.event }
    private var isLive: Bool { event.statusState == "in" }
    private var homeAbbr: String { event.homeCompetitor?.team?.abbreviation ?? "—" }
    private var awayAbbr: String { event.awayCompetitor?.team?.abbreviation ?? "—" }

    // Each abbreviation in its own club's true brand accent (dark-legible). Used
    // independently — not resolveMatchColors — so a team keeps its real color
    // here rather than being shifted for pair-distinctness (the crests already
    // disambiguate the two sides).
    private var homeColor: Color { clubStore.club(forAbbreviation: homeAbbr)?.accentColor ?? .dsFgPrimary }
    private var awayColor: Color { clubStore.club(forAbbreviation: awayAbbr)?.accentColor ?? .dsFgPrimary }

    var body: some View {
        HStack(spacing: 12) {
            crests
            VStack(alignment: .leading, spacing: 2) {
                matchupLine
                Text(detailLine)
                    .font(.system(size: 12))
                    .foregroundStyle(detailColor)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if isLive { liveBadge }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsBgCard)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusMd, style: .continuous))
    }

    // Mini home-v-away crests (bare logos — a team crest never gets a ring).
    private var crests: some View {
        HStack(spacing: 6) {
            TeamLogo(urlString: event.homeCompetitor?.team?.logo, teamAbbreviation: event.homeCompetitor?.team?.abbreviation, size: 28)
            Text("v")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.dsFgQuaternary)
            TeamLogo(urlString: event.awayCompetitor?.team?.logo, teamAbbreviation: event.awayCompetitor?.team?.abbreviation, size: 28)
        }
    }

    // "WAS vs POR" — abbreviations in each team's color.
    private var matchupLine: some View {
        HStack(spacing: 4) {
            Text(homeAbbr).foregroundStyle(homeColor)
            Text("vs").foregroundStyle(Color.dsFgTertiary)
            Text(awayAbbr).foregroundStyle(awayColor)
        }
        .font(.system(size: 14, weight: .semibold))
        .lineLimit(1)
    }

    private var liveBadge: some View {
        HStack(spacing: 5) {
            Circle().fill(Color.dsLive).frame(width: 7, height: 7)
            Text("LIVE")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.dsLive)
        }
    }

    // MARK: - Text

    /// Live: "45' · 1–0". Result: "FT · 2–1". Upcoming: "Tomorrow · 7:30 PM".
    private var detailLine: String {
        switch event.statusState {
        case "in":
            let clock = event.status?.displayClock ?? "LIVE"
            return [clock, scoreText].compactMap { $0 }.joined(separator: " · ")
        case "post":
            let detail = event.status?.type?.shortDetail ?? "FT"
            return [detail, scoreText].compactMap { $0 }.joined(separator: " · ")
        default:
            return [fixture.label.capitalized, kickoffTimeText].compactMap { $0 }.joined(separator: " · ")
        }
    }

    private var detailColor: Color {
        if isLive { return .dsLive }
        if !fixture.isResult, fixture.label == "TODAY" { return .dsAccent }
        return .dsFgSecondary
    }

    private var scoreText: String? {
        guard let home = event.homeCompetitor?.score,
              let away = event.awayCompetitor?.score else { return nil }
        return "\(home)–\(away)"
    }

    private var kickoffTimeText: String? {
        guard let kickoff = event.kickoff else { return nil }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: kickoff)
    }
}
