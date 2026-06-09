//
//  MatchDetailView.swift
//  NWSLApp
//
//  The detail screen for a single match, pushed when a MatchCard is tapped in the
//  Schedule. It adapts to the match's state — upcoming (kickoff time), live
//  (running score + clock), or finished (final score + FT) — and shows the teams
//  with their FULL names (cards use abbreviations to stay crisp; a detail screen
//  has room for the real names).
//
//  Data: built ENTIRELY from the `Event` already decoded from the season
//  scoreboard (handed in by the schedule) — no extra network request. A future
//  enhancement is ESPN's richer per-event endpoint (`/summary`) for lineups, goal
//  scorers, and match stats; that's deliberately out of scope here (see CLAUDE.md
//  What's-Next #6) so matches become tappable and useful with the data we have.
//
//  Navigation: it's a pushed screen on the Schedule's NavigationStack, so the
//  standard back button is its explicit back affordance (per the UI rules), and
//  it respects safe-area insets via a plain ScrollView.
//

import SwiftUI

struct MatchDetailView: View {
    let event: Event
    /// nil for ordinary NWSL matches (the only kind today). Mirrors MatchCard's
    /// dormant competition tag; renders if a value is ever supplied.
    var badge: CompetitionBadge? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if let badge { badgePill(badge) }
                headline
                matchup
                if hasInfo { infoCard }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(event.shortName ?? "Match")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Headline (date / live indicator)

    @ViewBuilder
    private var headline: some View {
        VStack(spacing: 8) {
            if event.statusState == "in" {
                liveIndicator
            }
            if let date = dateHeadline {
                Text(date)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var liveIndicator: some View {
        HStack(spacing: 6) {
            Circle().fill(.red).frame(width: 8, height: 8)
            Text(liveText)
                .font(.caption.weight(.bold))
                .foregroundStyle(.red)
        }
    }

    // MARK: - Matchup (crests + names + score/kickoff)

    private var matchup: some View {
        HStack(alignment: .top, spacing: 8) {
            teamColumn(event.homeCompetitor)
            centerColumn
            teamColumn(event.awayCompetitor)
        }
    }

    private func teamColumn(_ competitor: Competitor?) -> some View {
        VStack(spacing: 12) {
            TeamLogo(urlString: competitor?.team?.logo, size: 64)
            Text(name(for: competitor))
                .font(.headline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var centerColumn: some View {
        VStack(spacing: 6) {
            if showScores {
                Text(scoreLine)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                if event.statusState == "post" {
                    Text(event.status?.type?.shortDetail ?? "FT")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(kickoffTimeText)
                    .font(.title2.weight(.semibold))
                Text("Kickoff")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        // A little breathing room from the team columns; doesn't collapse on
        // single-digit scores or short times.
        .frame(minWidth: 84)
        .padding(.top, 18)   // sits centered against the crests above the names
    }

    // MARK: - Info card (venue + broadcast)

    private var infoCard: some View {
        VStack(spacing: 14) {
            if let venue = venueText {
                infoRow(icon: "mappin.and.ellipse", text: venue, dimmed: false)
            }
            if let channel = event.broadcastName {
                // A finished game's channel is informational only — dim it.
                infoRow(icon: "tv", text: channel, dimmed: event.statusState == "post")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func infoRow(icon: String, text: String, dimmed: Bool) -> some View {
        Label(text, systemImage: icon)
            .font(.subheadline)
            .foregroundStyle(dimmed ? .tertiary : .secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func badgePill(_ badge: CompetitionBadge) -> some View {
        Text(badge.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(badge.color.opacity(0.18), in: Capsule())
            .foregroundStyle(badge.color)
    }

    // MARK: - Derived values

    private var showScores: Bool {
        event.statusState == "in" || event.statusState == "post"
    }

    private var hasInfo: Bool {
        venueText != nil || event.broadcastName != nil
    }

    private func name(for competitor: Competitor?) -> String {
        competitor?.team?.displayName
            ?? competitor?.team?.shortDisplayName
            ?? competitor?.team?.abbreviation
            ?? "—"
    }

    private var scoreLine: String {
        let home = event.homeCompetitor?.score ?? "–"
        let away = event.awayCompetitor?.score ?? "–"
        return "\(home) – \(away)"
    }

    private var liveText: String {
        if let clock = event.status?.displayClock, !clock.isEmpty {
            return "LIVE · \(clock)"
        }
        return "LIVE"
    }

    /// "Saturday, June 6" — the matchday, shown for every state for context.
    private var dateHeadline: String? {
        guard let kickoff = event.kickoff else { return nil }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: kickoff)
    }

    /// "7:00 PM" — the focal value for upcoming matches.
    private var kickoffTimeText: String {
        guard let kickoff = event.kickoff else { return "TBD" }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: kickoff)
    }

    private var venueText: String? {
        switch (event.venueName, event.venueCity) {
        case let (name?, city?): return "\(name), \(city)"
        case let (name?, nil):   return name
        case let (nil, city?):   return city
        default:                 return nil
        }
    }
}
