//
//  ComingUpRow.swift
//  NWSLApp
//
//  Home's Module 4 ("Coming up") — a COMPACT schedule row, one per followed team
//  (per Reference/Design/home-tab-design-spec.md, which shrank the old big match
//  cards down to a strip that just answers "when do my teams play next?"; the full
//  detail lives in the Schedule tab). A followed team's crest + the matchup + a
//  time-aware line ("Tomorrow · 7:30 PM"), with a live indicator or a compact
//  result line when relevant.
//
//  Reuses HomeViewModel.FollowedFixture (the same derivation that fed the old
//  NextMatchCard) so Module 4 is a lighter rendering of data Home already has —
//  no extra fetch.
//

import SwiftUI

struct ComingUpRow: View {
    let fixture: HomeViewModel.FollowedFixture

    private var event: Event { fixture.event }
    private var isLive: Bool { event.statusState == "in" }

    var body: some View {
        HStack(spacing: 12) {
            TeamLogo(urlString: fixture.club.logoURL, size: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(matchup)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(detailLine)
                    .font(.caption)
                    .foregroundStyle(detailColor)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if isLive {
                liveBadge
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var liveBadge: some View {
        HStack(spacing: 5) {
            Circle().fill(.red).frame(width: 7, height: 7)
            Text("LIVE")
                .font(.caption.weight(.bold))
                .foregroundStyle(.red)
        }
    }

    // MARK: - Text

    /// "Washington vs Portland" — short names where available (no invented
    /// nicknames; abbreviations are the fallback, matching the app convention).
    private var matchup: String {
        let home = teamLabel(event.homeCompetitor)
        let away = teamLabel(event.awayCompetitor)
        return "\(home) vs \(away)"
    }

    private func teamLabel(_ competitor: Competitor?) -> String {
        competitor?.team?.shortDisplayName
            ?? competitor?.team?.abbreviation
            ?? competitor?.team?.displayName
            ?? "—"
    }

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
        if isLive { return .red }
        if !fixture.isResult, fixture.label == "TODAY" { return .accentColor }
        return .secondary
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
