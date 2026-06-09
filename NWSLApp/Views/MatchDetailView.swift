//
//  MatchDetailView.swift
//  NWSLApp
//
//  The detail screen for a single match, pushed when a MatchCard is tapped in the
//  Schedule. It adapts to the match's state via MatchDetailViewModel.temporalState:
//
//   • Past  — a tabbed recap: SUMMARY (events timeline), LINEUPS (formation +
//             subs), STATS (head-to-head comparison bars). All from one ESPN
//             `/summary` fetch.
//   • Live  — the same tabs (labelled EVENTS) with a pulsing LIVE indicator +
//             running clock; the data refreshes on a 30s poll.
//   • Future— a single-scroll preview: kickoff, venue/broadcast, a season
//             comparison, and recent form — derived from the shared MatchStore,
//             not the summary endpoint (which is empty before a match).
//
//  The scoreboard `Event` is always in hand, so the header renders instantly with
//  no network; the richer `/summary` layers on top. If that fetch fails the
//  screen degrades to the header alone rather than a blank wall (UI rules: never
//  a broken screen). It rides the Schedule's NavigationStack, so the standard
//  back button is its back affordance.
//

import SwiftUI

struct MatchDetailView: View {
    @State private var viewModel: MatchDetailViewModel
    /// nil for ordinary NWSL matches (the only kind today). Mirrors MatchCard's
    /// dormant competition tag; renders if a value is ever supplied.
    private let badge: CompetitionBadge?

    @Environment(MatchStore.self) private var matchStore
    @Environment(\.openURL) private var openURL

    @State private var tab: DetailTab = .summary

    init(event: Event, badge: CompetitionBadge? = nil) {
        _viewModel = State(initialValue: MatchDetailViewModel(event: event))
        self.badge = badge
        #if DEBUG
        // TEMP (match-detail-v2 verification): pre-select a tab for deterministic
        // screenshots via the MATCH_DETAIL_TAB env var. DELETE with the harness.
        if let raw = ProcessInfo.processInfo.environment["MATCH_DETAIL_TAB"],
           let preselected = DetailTab(rawValue: raw) {
            _tab = State(initialValue: preselected)
        }
        #endif
    }

    private enum DetailTab: String, CaseIterable, Hashable {
        case summary = "Summary"
        case lineups = "Lineups"
        case stats = "Stats"
    }

    private var event: Event { viewModel.event }

    var body: some View {
        Group {
            switch viewModel.temporalState {
            case .past, .live: tabbedLayout
            case .future:      futureLayout
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(event.shortName ?? "Match")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // First load only; the live poll (task) re-triggers explicitly.
            if case .idle = viewModel.summaryState { await viewModel.loadSummary() }
        }
    }

    // MARK: - Past / Live layout (pinned header + tabs, only the section scrolls)

    private var tabbedLayout: some View {
        VStack(spacing: 0) {
            header

            Picker("Section", selection: $tab) {
                ForEach(DetailTab.allCases, id: \.self) { tab in
                    Text(tabLabel(tab)).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal)
            .padding(.bottom, 12)

            Divider()

            tabContent
        }
    }

    /// Live relabels the events tab to "Events"; otherwise the raw case name.
    private func tabLabel(_ tab: DetailTab) -> String {
        if tab == .summary && viewModel.temporalState == .live { return "Events" }
        return tab.rawValue
    }

    @ViewBuilder
    private var tabContent: some View {
        ScrollView {
            switch viewModel.summaryState {
            case .idle, .loading:
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            case .error(let message):
                summaryError(message)
            case .loaded(let summary):
                switch tab {
                case .summary: summaryTab(summary)
                case .lineups: lineupsTab(summary)
                case .stats:   statsTab(summary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Summary tab (events timeline)

    @ViewBuilder
    private func summaryTab(_ summary: MatchSummary) -> some View {
        let events = summary.timelineEvents
        if events.isEmpty {
            emptyState("No key events yet.")
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(events.enumerated()), id: \.offset) { index, event in
                    EventTimelineRow(event: event)
                    if index < events.count - 1 { Divider() }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding()
        }
    }

    // MARK: - Lineups tab (starters + substitutes)
    //
    // Task #3 will add a FormationPitchView above the starters list for known
    // formation strings; this list rendering stays as the permanent fallback for
    // unknown formations (never a broken pitch).

    @ViewBuilder
    private func lineupsTab(_ summary: MatchSummary) -> some View {
        if summary.homeRoster == nil && summary.awayRoster == nil {
            emptyState("Lineups aren't available for this match.")
        } else {
            VStack(spacing: 24) {
                if let home = summary.homeRoster { rosterBlock(home) }
                if let away = summary.awayRoster { rosterBlock(away) }
            }
            .padding()
        }
    }

    private func rosterBlock(_ roster: MatchRoster) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(roster.team?.displayName ?? "—")
                    .font(.headline)
                Spacer()
                if let formation = roster.formation {
                    Text(formation)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                }
            }

            lineupList("Starting XI", players: roster.starters)
            if !roster.substitutes.isEmpty {
                lineupList("Substitutes", players: roster.substitutes)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func lineupList(_ title: String, players: [MatchPlayer]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(players.enumerated()), id: \.offset) { _, player in
                HStack(spacing: 10) {
                    Text(player.jersey ?? "–")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .trailing)
                    Text(player.athlete?.displayName ?? "—")
                        .font(.subheadline)
                    if player.subbedOut == true {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.red.opacity(0.7))
                    }
                    if player.subbedIn == true {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green.opacity(0.7))
                    }
                    Spacer(minLength: 0)
                    if let pos = player.position?.abbreviation {
                        Text(pos)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    // MARK: - Stats tab (head-to-head comparison bars)

    @ViewBuilder
    private func statsTab(_ summary: MatchSummary) -> some View {
        let rows = statRows(summary)
        if rows.isEmpty {
            emptyState("Match stats aren't available.")
        } else {
            VStack(spacing: 18) {
                ForEach(rows) { row in
                    StatComparisonBar(
                        label: row.label,
                        home: row.home, away: row.away,
                        homeDisplay: row.homeDisplay, awayDisplay: row.awayDisplay,
                        homeColor: teamColor(homeHex), awayColor: teamColor(awayHex)
                    )
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding()
        }
    }

    /// The stats we surface, in display order. `percent` stats are normalized so
    /// "0.9" (pass accuracy) and "61" (possession) both read as a percentage.
    private struct StatSpec { let name: String; let label: String; let percent: Bool }
    private static let statSpecs: [StatSpec] = [
        .init(name: "possessionPct", label: "Possession",    percent: true),
        .init(name: "totalShots",    label: "Shots",         percent: false),
        .init(name: "shotsOnTarget", label: "On Target",     percent: false),
        .init(name: "wonCorners",    label: "Corners",       percent: false),
        .init(name: "totalPasses",   label: "Passes",        percent: false),
        .init(name: "passPct",       label: "Pass Accuracy", percent: true),
        .init(name: "foulsCommitted",label: "Fouls",         percent: false),
        .init(name: "totalTackles",  label: "Tackles",       percent: false),
    ]

    private struct StatRow: Identifiable {
        let id = UUID()
        let label: String
        let home: Double, away: Double
        let homeDisplay: String, awayDisplay: String
    }

    private func statRows(_ summary: MatchSummary) -> [StatRow] {
        guard let homeBox = summary.homeBoxscore, let awayBox = summary.awayBoxscore else { return [] }
        return Self.statSpecs.compactMap { spec in
            guard let h = number(homeBox.stat(spec.name)?.displayValue),
                  let a = number(awayBox.stat(spec.name)?.displayValue) else { return nil }
            return StatRow(
                label: spec.label,
                home: spec.percent ? normalizedPercent(h) : h,
                away: spec.percent ? normalizedPercent(a) : a,
                homeDisplay: spec.percent ? percentString(h) : intString(h),
                awayDisplay: spec.percent ? percentString(a) : intString(a)
            )
        }
    }

    private func number(_ s: String?) -> Double? { s.flatMap(Double.init) }
    /// ESPN sends percentages two ways: 0–1 fractions ("0.9") and 0–100 ("61").
    private func normalizedPercent(_ v: Double) -> Double { v <= 1 ? v * 100 : v }
    private func percentString(_ v: Double) -> String { "\(Int(normalizedPercent(v).rounded()))%" }
    private func intString(_ v: Double) -> String { "\(Int(v.rounded()))" }

    // MARK: - Future layout (preview)
    //
    // Minimal for now (header + match info); task #4 adds the Season Comparison
    // and Recent Form sections derived from the shared MatchStore.

    private var futureLayout: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                if hasInfo { infoCard }
            }
            .padding(.bottom, 20)
        }
    }

    // MARK: - Header (shared across all states)

    private var header: some View {
        VStack(spacing: 16) {
            if let badge { badgePill(badge) }

            stateLine

            HStack(alignment: .top, spacing: 8) {
                teamColumn(event.homeCompetitor, hex: homeHex)
                centerColumn
                teamColumn(event.awayCompetitor, hex: awayHex)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
        .background(headerBackground)
    }

    private var headerBackground: some View {
        LinearGradient(
            colors: [wash(homeHex), Color.black.opacity(0.12), wash(awayHex)],
            startPoint: .leading, endPoint: .trailing
        )
        .background(Color(.secondarySystemGroupedBackground))
    }

    @ViewBuilder
    private var stateLine: some View {
        if viewModel.temporalState == .live {
            liveIndicator
        } else if let date = dateHeadline {
            Text(date)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
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

    private func teamColumn(_ competitor: Competitor?, hex: String?) -> some View {
        VStack(spacing: 12) {
            TeamLogo(urlString: competitor?.team?.logo, size: 64)
                .padding(4)
                .overlay(
                    Circle().stroke(crestBorder(hex), lineWidth: 2)
                )
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
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
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
        .frame(minWidth: 84)
        .padding(.top, 18)
    }

    // MARK: - Info card (venue + broadcast)

    private var infoCard: some View {
        VStack(spacing: 14) {
            if let venue = venueText {
                infoRow(icon: "mappin.and.ellipse", text: venue, dimmed: false)
            }
            if let channel = event.broadcastName {
                infoRow(icon: "tv", text: channel, dimmed: event.statusState == "post")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 20)
    }

    private func infoRow(icon: String, text: String, dimmed: Bool) -> some View {
        Label(text, systemImage: icon)
            .font(.subheadline)
            .foregroundStyle(dimmed ? .tertiary : .secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Small shared pieces

    private func summaryError(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try again") {
                Task { await viewModel.loadSummary() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .padding(.horizontal, 32)
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
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

    /// Team accent hexes from the loaded summary (nil until it arrives / for
    /// pre-match), used to tint the header crest borders + stat bars.
    private var homeHex: String? { viewModel.summary?.homeRoster?.team?.color ?? viewModel.summary?.homeBoxscore?.team?.color }
    private var awayHex: String? { viewModel.summary?.awayRoster?.team?.color ?? viewModel.summary?.awayBoxscore?.team?.color }

    /// A team color for bars/dots that always reads on the dark canvas (dark
    /// brand colors like black are lifted); the app accent when hex is unknown.
    private func teamColor(_ hex: String?) -> Color { Color.teamFillOnDark(hex: hex) }
    /// A subtle header wash — clear (transparent over the dark base) when unknown.
    private func wash(_ hex: String?) -> Color { hex == nil ? .clear : Color.teamFillOnDark(hex: hex).opacity(0.30) }
    /// Crest border — the team color (lifted to read on dark), or a neutral
    /// separator when unknown.
    private func crestBorder(_ hex: String?) -> Color { hex == nil ? Color(.separator) : Color.teamFillOnDark(hex: hex) }

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

    private var dateHeadline: String? {
        guard let kickoff = event.kickoff else { return nil }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: kickoff)
    }

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
