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
    @State private var pulse = false
    @Namespace private var tabUnderline

    init(event: Event, badge: CompetitionBadge? = nil) {
        _viewModel = State(initialValue: MatchDetailViewModel(event: event))
        self.badge = badge
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
        // Empty inline title: the header already shows both crests + names, so
        // the nav bar stays just the back chevron (matches TeamDetailView).
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // First load (shows a spinner), then poll silently every 30s while
            // the match is live so events/score/clock fill in — the proxy's TTL
            // makes this cheap once /summary is proxied.
            if case .idle = viewModel.summaryState { await viewModel.loadSummary() }
            while !Task.isCancelled && viewModel.temporalState == .live {
                try? await Task.sleep(for: .seconds(30))
                if Task.isCancelled { break }
                await viewModel.refresh()
            }
        }
    }

    // MARK: - Past / Live layout (pinned header + tabs, only the section scrolls)

    private var tabbedLayout: some View {
        VStack(spacing: 0) {
            header
            tabBar
            Divider()
            tabContent
        }
    }

    // ALL-CAPS labels with a sliding colored underline on the active tab — no
    // segmented-control chrome (matches the mockup). Underline is the home team's
    // color, or red while live.
    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(DetailTab.allCases, id: \.self) { item in
                Button { tab = item } label: {
                    VStack(spacing: 6) {
                        Text(tabLabel(item).uppercased())
                            .font(.caption.weight(.semibold))
                            .tracking(0.6)
                            .foregroundStyle(tab == item ? Color.primary : Color.secondary)
                        ZStack {
                            Rectangle().fill(.clear).frame(height: 2)
                            if tab == item {
                                Rectangle()
                                    .fill(underlineColor)
                                    .frame(height: 2)
                                    .matchedGeometryEffect(id: "tabUnderline", in: tabUnderline)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: tab)
        .padding(.horizontal)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    private var underlineColor: Color {
        viewModel.temporalState == .live ? .red : matchColors.home.fill
    }

    /// Live relabels the events tab to "Events"; otherwise the raw case name.
    private func tabLabel(_ tab: DetailTab) -> String {
        if tab == .summary && viewModel.temporalState == .live { return "Events" }
        return tab.rawValue
    }

    @ViewBuilder
    private var tabContent: some View {
        ScrollView {
            VStack(spacing: 0) {
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

                if viewModel.temporalState == .live {
                    Text("Updates every ~30 seconds")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)
                        .padding(.bottom, 16)
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
        let homeID = summary.homeBoxscore?.team?.id ?? summary.homeRoster?.team?.id
        let awayID = summary.awayBoxscore?.team?.id ?? summary.awayRoster?.team?.id
        let homeAbbr = summary.homeBoxscore?.team?.abbreviation ?? summary.homeRoster?.team?.abbreviation
        let awayAbbr = summary.awayBoxscore?.team?.abbreviation ?? summary.awayRoster?.team?.abbreviation

        VStack(spacing: 14) {
            if events.isEmpty {
                emptyState("No key events yet.")
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(events.enumerated()), id: \.offset) { index, event in
                        EventTimelineRow(
                            event: event,
                            homeTeamID: homeID, awayTeamID: awayID,
                            homeAbbr: homeAbbr, awayAbbr: awayAbbr
                        )
                        if index < events.count - 1 { Divider() }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            if let officials = officialsText(summary) {
                Text(officials)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding()
    }

    private func officialsText(_ summary: MatchSummary) -> String? {
        let names = (summary.gameInfo?.officials ?? [])
            .sorted { ($0.order ?? .max) < ($1.order ?? .max) }
            .compactMap { $0.displayName ?? $0.fullName }
        guard !names.isEmpty else { return nil }
        return "Officials: " + names.joined(separator: " · ")
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
        let accent = roster.homeAway == "away" ? matchColors.away : matchColors.home
        return VStack(alignment: .leading, spacing: 12) {
            // One centered, uppercased line: "WASHINGTON SPIRIT — 4-2-3-1".
            Text(formationHeader(roster))
                .font(.caption.weight(.semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)

            // Pitch when we can place all 11 by position; the list is the
            // permanent fallback (never a broken pitch).
            if FormationPitchView.supports(formation: roster.formation, players: roster.starters) {
                FormationPitchView(
                    formation: roster.formation,
                    players: roster.starters,
                    accent: accent
                )
            } else {
                lineupList("Starting XI", players: roster.starters)
            }

            if !roster.substitutes.isEmpty {
                substituteChips(roster.substitutes)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func formationHeader(_ roster: MatchRoster) -> String {
        let team = (roster.team?.displayName ?? "—").uppercased()
        if let formation = roster.formation { return "\(team) — \(formation)" }
        return team
    }

    // Compact wrapping chips: "18 MacIver  14 Carle 61'". The minute shows for a
    // player who came on. Reuses FlowLayout so they wrap across lines.
    private func substituteChips(_ subs: [MatchPlayer]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SUBSTITUTES")
                .font(.caption.weight(.semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 6) {
                ForEach(Array(subs.enumerated()), id: \.offset) { _, player in
                    substituteChip(player)
                }
            }
        }
    }

    private func substituteChip(_ player: MatchPlayer) -> some View {
        HStack(spacing: 4) {
            Text(player.jersey ?? "–")
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text(subLastName(player))
                .font(.caption2)
            if player.subbedIn == true {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.green.opacity(0.8))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.tertiarySystemFill), in: Capsule())
    }

    private func subLastName(_ player: MatchPlayer) -> String {
        let candidates = [player.athlete?.lastName, player.athlete?.shortName, player.athlete?.displayName]
        for name in candidates {
            if let word = name?.split(separator: " ").last, !word.isEmpty { return String(word) }
        }
        return player.jersey ?? "—"
    }

    private func lineupList(_ title: String, players: [MatchPlayer]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.5)
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
            VStack(spacing: 16) {
                // Team-abbreviation header anchors which side is which, in color.
                HStack {
                    Text(summary.homeBoxscore?.team?.abbreviation ?? "—")
                        .foregroundStyle(matchColors.home.fill)
                    Spacer()
                    Text(summary.awayBoxscore?.team?.abbreviation ?? "—")
                        .foregroundStyle(matchColors.away.fill)
                }
                .font(.caption.weight(.bold))

                VStack(spacing: 18) {
                    ForEach(rows) { row in
                        StatComparisonBar(
                            label: row.label,
                            home: row.home, away: row.away,
                            homeDisplay: row.homeDisplay, awayDisplay: row.awayDisplay,
                            homeColor: matchColors.home.fill, awayColor: matchColors.away.fill
                        )
                    }
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
        .init(name: "shotsOnTarget", label: "Shots on Target", percent: false),
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
    // Header + match info, then a season comparison and recent form — both
    // derived from the shared MatchStore season (no summary endpoint, which is
    // empty before kickoff). Only the stats we can compute from results are
    // shown; possession/shots/etc. season averages are intentionally omitted.

    private var futureLayout: some View {
        let preview = viewModel.buildPreview(season: matchStore.events)
        return ScrollView {
            VStack(spacing: 24) {
                header
                if hasInfo { infoCard }
                if preview.hasData {
                    seasonComparison(preview)
                    recentForm(preview)
                }
            }
            .padding(.bottom, 20)
        }
    }

    private func seasonComparison(_ preview: MatchPreview) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Season Comparison")
                .font(.headline)
            comparisonBar("Goals / Match", preview.home.goalsPerMatch, preview.away.goalsPerMatch)
            comparisonBar("Conceded / Match", preview.home.concededPerMatch, preview.away.concededPerMatch)
            comparisonBar("Points / Game", preview.home.pointsPerGame, preview.away.pointsPerGame)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 20)
    }

    private func comparisonBar(_ label: String, _ home: Double, _ away: Double) -> some View {
        StatComparisonBar(
            label: label, home: home, away: away,
            homeDisplay: oneDecimal(home), awayDisplay: oneDecimal(away),
            homeColor: matchColors.home.fill, awayColor: matchColors.away.fill
        )
    }

    private func recentForm(_ preview: MatchPreview) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Recent Form")
                .font(.headline)
            formRow(name: name(for: event.homeCompetitor), form: preview.home)
            formRow(name: name(for: event.awayCompetitor), form: preview.away)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 20)
    }

    private func formRow(name: String, form: TeamSeasonForm) -> some View {
        HStack(spacing: 10) {
            Text(name)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Spacer(minLength: 8)
            if form.recent.isEmpty {
                Text("No matches yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 5) {
                    ForEach(Array(form.recent.enumerated()), id: \.offset) { _, result in
                        formBadge(result)
                    }
                }
            }
        }
    }

    private func formBadge(_ result: MatchResult) -> some View {
        let (letter, color): (String, Color) = switch result {
        case .win:  ("W", .green)
        case .draw: ("D", .gray)
        case .loss: ("L", .red)
        }
        return Text(letter)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(color.opacity(0.85), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private func oneDecimal(_ v: Double) -> String { String(format: "%.1f", v) }

    // MARK: - Header (shared across all states)

    private var header: some View {
        VStack(spacing: 16) {
            if let badge { badgePill(badge) }

            stateLine

            HStack(alignment: .top, spacing: 8) {
                teamColumn(event.homeCompetitor, border: crestBorder(matchColors.home))
                centerColumn
                teamColumn(event.awayCompetitor, border: crestBorder(matchColors.away))
            }

            // Past/live show venue · broadcast · attendance inline here (future
            // keeps its own info card below the preview).
            if viewModel.temporalState != .future, hasCompactInfo {
                compactInfoRow
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
        .background(headerBackground)
    }

    private var hasCompactInfo: Bool {
        event.venueName != nil || event.broadcastName != nil || attendanceText != nil
    }

    private var compactInfoRow: some View {
        HStack(spacing: 14) {
            if let venue = event.venueName {
                Label(venue, systemImage: "mappin.and.ellipse").lineLimit(1)
            }
            if let channel = event.broadcastName {
                Label(channel, systemImage: "tv").lineLimit(1)
            }
            if let attendance = attendanceText {
                Label(attendance, systemImage: "person.3.fill").lineLimit(1)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
    }

    private var attendanceText: String? {
        guard let attendance = viewModel.summary?.gameInfo?.attendance else { return nil }
        return NumberFormatter.localizedString(from: NSNumber(value: attendance), number: .decimal)
    }

    private var headerBackground: some View {
        // A subtle left→right wash of the two team colors with a wide dark center,
        // so the colors read as identity tint, not a vivid split.
        LinearGradient(
            stops: [
                .init(color: wash(matchColors.home), location: 0.0),
                .init(color: Color.black.opacity(0.25), location: 0.35),
                .init(color: Color.black.opacity(0.25), location: 0.65),
                .init(color: wash(matchColors.away), location: 1.0),
            ],
            startPoint: .leading, endPoint: .trailing
        )
        .background(Color(.secondarySystemGroupedBackground))
    }

    @ViewBuilder
    private var stateLine: some View {
        if viewModel.temporalState == .live {
            VStack(spacing: 4) {
                liveIndicator
                if let clockLine {
                    Text(clockLine)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        } else if let date = dateHeadline {
            Text(date)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private var liveIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
                .opacity(pulse ? 0.3 : 1)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
            Text("LIVE")
                .font(.caption.weight(.bold))
                .foregroundStyle(.red)
        }
        .onAppear { pulse = true }
    }

    /// "63:18 — Second Half": the running clock + the period name from ESPN.
    private var clockLine: String? {
        let clock = event.status?.displayClock
        let period = event.status?.type?.description
        let parts = [clock, period].compactMap { ($0?.isEmpty == false) ? $0 : nil }
        return parts.isEmpty ? nil : parts.joined(separator: " — ")
    }

    private func teamColumn(_ competitor: Competitor?, border: Color) -> some View {
        VStack(spacing: 12) {
            TeamLogo(urlString: competitor?.team?.logo, size: 64)
                .padding(4)
                .overlay(
                    Circle().stroke(border, lineWidth: 2)
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
                    .font(.system(size: 44, weight: .heavy))
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
                broadcastRow(channel)
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

    // Broadcast row: a tappable "where to watch" link when recognized (no
    // navigation to compete with here, unlike the card), dimmed/plain once the
    // match is over.
    @ViewBuilder
    private func broadcastRow(_ channel: String) -> some View {
        let isPast = event.statusState == "post"
        if !isPast, let url = BroadcastLink.url(for: channel) {
            Button { openURL(url) } label: {
                Label(channel, systemImage: "tv")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
        } else {
            infoRow(icon: "tv", text: channel, dimmed: isPast)
        }
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

    private var homeTeamColorID: String? { viewModel.summary?.homeRoster?.team?.id ?? viewModel.summary?.homeBoxscore?.team?.id }
    private var awayTeamColorID: String? { viewModel.summary?.awayRoster?.team?.id ?? viewModel.summary?.awayBoxscore?.team?.id }

    /// Team color hexes from the loaded summary (nil until it arrives / pre-match),
    /// with a brand-color override applied first for clubs ESPN gets wrong (see
    /// TeamBrandColors — e.g. Angel City's Sol Rosa coral).
    private var homeHex: String? { TeamBrandColors.primary(for: homeTeamColorID) ?? viewModel.summary?.homeRoster?.team?.color ?? viewModel.summary?.homeBoxscore?.team?.color }
    private var awayHex: String? { TeamBrandColors.primary(for: awayTeamColorID) ?? viewModel.summary?.awayRoster?.team?.color ?? viewModel.summary?.awayBoxscore?.team?.color }
    private var homeAltHex: String? { TeamBrandColors.alternate(for: homeTeamColorID) ?? viewModel.summary?.homeRoster?.team?.alternateColor ?? viewModel.summary?.homeBoxscore?.team?.alternateColor }
    private var awayAltHex: String? { TeamBrandColors.alternate(for: awayTeamColorID) ?? viewModel.summary?.awayRoster?.team?.alternateColor ?? viewModel.summary?.awayBoxscore?.team?.alternateColor }

    /// True once the summary has supplied at least one team color.
    private var hasTeamColors: Bool { homeHex != nil || awayHex != nil || homeAltHex != nil || awayAltHex != nil }

    /// Both teams' resolved colors for this match — each legible on dark and
    /// guaranteed distinct from the other. The single source for every side-by-side
    /// team-color callsite: formation dots, stat bars + values, the stats header,
    /// and the header wash/crest borders.
    private var matchColors: (home: ResolvedTeamColor, away: ResolvedTeamColor) {
        Color.resolveMatchColors(
            homePrimary: homeHex, homeAlt: homeAltHex,
            awayPrimary: awayHex, awayAlt: awayAltHex
        )
    }

    /// Crest border / header wash respect "no tint until the summary's colors
    /// arrive" (the resolver always returns a fallback, so gate on hasTeamColors).
    private func crestBorder(_ resolved: ResolvedTeamColor) -> Color { hasTeamColors ? resolved.fill : Color(.separator) }
    private func wash(_ resolved: ResolvedTeamColor) -> Color { hasTeamColors ? resolved.fill.opacity(0.30) : .clear }

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
