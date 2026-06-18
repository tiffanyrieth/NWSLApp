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
    /// The competition this match belongs to — drives the header competition pill,
    /// the info-row competition name, and neutral rendering of non-NWSL sides.
    /// Defaults to `.nwsl` so the 99% schedule path is unchanged.
    private let competition: CompetitionType

    @Environment(MatchStore.self) private var matchStore

    @State private var tab: DetailTab = .summary
    @State private var pulse = false
    @Namespace private var tabUnderline

    init(event: Event, competition: CompetitionType = .nwsl) {
        _viewModel = State(initialValue: MatchDetailViewModel(event: event))
        self.competition = competition
    }

    private enum DetailTab: String, CaseIterable, Hashable {
        case summary = "Play by Play"
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
        .background(Color.dsBgPrimary)
        // Bare ‹ chevron, no centered title: the full-bleed header (crests + score)
        // carries identity. `nativeBackButton()` keeps the swipe gesture via the editor
        // toolbar role (see DSText).
        .nativeBackButton()
        // Transparent nav bar so the team-color wash reads full-bleed up to the top.
        // Deliberately TRANSPARENT, not hidden: hiding the bar is what breaks the
        // interactive swipe-back gesture (the classic gotcha) — keeping the bar
        // present preserves the swipe while the wash shows through behind it.
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
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
            // Only show tabs that actually have data (a sparse non-NWSL match may
            // have no lineups/stats) — and drop the bar entirely when only Play-by-
            // Play remains, so there's no lone, pointless tab.
            if visibleTabs.count > 1 {
                tabBar
                Divider()
            }
            tabContent
        }
    }

    /// Which tabs have data to show. Before the summary loads we optimistically show
    /// all three (the NWSL norm); once loaded, Lineups/Stats appear only when present.
    private var visibleTabs: [DetailTab] {
        guard let summary = viewModel.summary else { return DetailTab.allCases }
        var tabs: [DetailTab] = [.summary]
        if summary.homeRoster != nil || summary.awayRoster != nil { tabs.append(.lineups) }
        if !statRows(summary).isEmpty { tabs.append(.stats) }
        return tabs
    }

    /// The selected tab, snapped back to Play-by-Play if its tab vanished after load
    /// (e.g. user was on Stats, then a sparse summary arrived without stats).
    private var effectiveTab: DetailTab {
        visibleTabs.contains(tab) ? tab : .summary
    }

    // ALL-CAPS labels with a sliding colored underline on the active tab — no
    // segmented-control chrome (matches the mockup). Underline is the home team's
    // color, or red while live.
    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(visibleTabs, id: \.self) { item in
                Button { tab = item } label: {
                    VStack(spacing: 6) {
                        Text(tabLabel(item).uppercased())
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(1)
                            .foregroundStyle(effectiveTab == item ? Color.dsFgPrimary : Color.dsFgTertiary)
                        ZStack {
                            Rectangle().fill(.clear).frame(height: 2)
                            if effectiveTab == item {
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
        // Cyan for a past recap, orange while live (the design's state accents).
        viewModel.temporalState == .live ? .dsStateClock : .dsStateKickoff
    }

    private func tabLabel(_ tab: DetailTab) -> String { tab.rawValue }

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
                    switch effectiveTab {
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
        .background(Color.dsBgPrimary)
    }

    // MARK: - Summary tab (events timeline)

    @ViewBuilder
    private func summaryTab(_ summary: MatchSummary) -> some View {
        let events = summary.timelineEvents
        let homeID = summary.homeBoxscore?.team?.id ?? summary.homeRoster?.team?.id
        // Crest + abbreviation per side for each event row's left color box.
        let homeCrest = event.homeCompetitor?.team?.logo
        let awayCrest = event.awayCompetitor?.team?.logo
        let homeAbbr = event.homeCompetitor?.team?.abbreviation ?? summary.homeRoster?.team?.abbreviation
        let awayAbbr = event.awayCompetitor?.team?.abbreviation ?? summary.awayRoster?.team?.abbreviation
        // Running scoreline per goal (chronological events).
        let scorelines = goalScorelines(events, homeID: homeID)

        VStack(spacing: 14) {
            if events.isEmpty {
                // A real match with no goals/cards yet says "No key events yet"; a
                // truly sparse fixture (no lineups, no stats either — common for a
                // non-NWSL match) gets the gentler "will be updated" copy.
                let hasRichData = summary.homeRoster != nil || summary.awayRoster != nil
                    || !statRows(summary).isEmpty
                emptyState(hasRichData ? "No key events yet."
                                       : "Match details will be updated when available.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(events.enumerated()), id: \.offset) { index, ev in
                        let isHome = ev.team?.id == homeID
                        EventTimelineRow(
                            event: ev,
                            minuteColor: underlineColor,
                            teamColor: isHome ? matchColors.home.fill : matchColors.away.fill,
                            crestURL: isHome ? homeCrest : awayCrest,
                            crestAbbr: isHome ? homeAbbr : awayAbbr,
                            score: scorelines[index]
                        )
                        if index < events.count - 1 { Divider().padding(.leading, 2) }
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.dsBgCard)
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

    /// Running scoreline ("home–away") at each goal, keyed by event index. Walks
    /// the chronological events, crediting the scoring side by `team.id`.
    private func goalScorelines(_ events: [KeyEvent], homeID: String?) -> [Int: String] {
        var home = 0, away = 0
        var map: [Int: String] = [:]
        for (index, ev) in events.enumerated() {
            let isGoal = ev.scoringPlay == true || (ev.type?.type ?? "").contains("goal")
            guard isGoal else { continue }
            if ev.team?.id == homeID { home += 1 } else { away += 1 }
            map[index] = "\(home)\u{2013}\(away)"   // en dash
        }
        return map
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
        } else if let homeR = summary.homeRoster, let awayR = summary.awayRoster,
                  CombinedPitchView.supports(home: side(homeR, matchColors.home),
                                             away: side(awayR, matchColors.away)) {
            // Both XIs on ONE pitch (home top / away bottom), then each bench.
            VStack(spacing: 16) {
                combinedPitchCard(homeR, awayR)
                if !homeR.substitutes.isEmpty { substitutesCard(homeR) }
                if !awayR.substitutes.isEmpty { substitutesCard(awayR) }
            }
            .padding()
        } else {
            // Fallback: per-team blocks (a single pitch where placeable, else a list).
            VStack(spacing: 24) {
                if let home = summary.homeRoster { rosterBlock(home) }
                if let away = summary.awayRoster { rosterBlock(away) }
            }
            .padding()
        }
    }

    private func side(_ roster: MatchRoster, _ accent: ResolvedTeamColor) -> CombinedPitchView.Side {
        CombinedPitchView.Side(
            abbr: roster.team?.abbreviation ?? "—",
            formation: roster.formation,
            players: roster.starters,
            accent: accent
        )
    }

    private func combinedPitchCard(_ home: MatchRoster, _ away: MatchRoster) -> some View {
        CombinedPitchView(home: side(home, matchColors.home), away: side(away, matchColors.away))
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.dsBgCard)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func substitutesCard(_ roster: MatchRoster) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // "BENCH" — the unused/used substitutes. ("Substitutes" was a mislabel for
            // a finished match: it's the bench, not who came on.)
            Text("\((roster.team?.displayName ?? roster.team?.abbreviation ?? "—").uppercased()) BENCH")
                .font(.caption.weight(.semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 6) {
                ForEach(Array(roster.substitutes.enumerated()), id: \.offset) { _, player in
                    substituteChip(player)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsBgCard)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
        .background(Color.dsBgCard)
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
            Text("BENCH")
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
            .background(Color.dsBgCard)
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
                futureInfoGrid
                HowToWatchCard(broadcast: event.broadcastName)
                    .padding(.horizontal, 20)
                if preview.hasData {
                    seasonComparison(preview)
                    recentForm(preview)
                }
            }
            .padding(.bottom, 20)
        }
    }

    // Venue / Broadcast / Competition tiles (weather deferred). Each renders only
    // when its value is known, so a sparse fixture degrades gracefully.
    private var futureInfoGrid: some View {
        HStack(spacing: 10) {
            if let venue = venueText {
                MDInfoCard(label: "Venue", value: venue)
            }
            if let channel = event.broadcastName {
                MDInfoCard(label: "Broadcast", value: channel)
            }
            MDInfoCard(label: "Competition",
                       value: competition.displayLabel ?? "NWSL Regular Season")
        }
        .padding(.horizontal, 20)
    }

    private func seasonComparison(_ preview: MatchPreview) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Season comparison")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.dsFgPrimary)
            // Crest + abbreviation per side (two-team context — never full names).
            HStack {
                crestAbbr(event.homeCompetitor, color: matchColors.home.fill)
                Spacer()
                crestAbbr(event.awayCompetitor, color: matchColors.away.fill)
            }
            VStack(spacing: 18) {
                comparisonBar("Goals / Match", preview.home.goalsPerMatch, preview.away.goalsPerMatch)
                comparisonBar("Conceded / Match", preview.home.concededPerMatch, preview.away.concededPerMatch)
                comparisonBar("Points / Game", preview.home.pointsPerGame, preview.away.pointsPerGame)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsBgCard)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 20)
    }

    /// Crest + abbreviation in the team's color — the two-team-context identity
    /// (CLAUDE.md: never full club names, never crest-less text in a matchup).
    private func crestAbbr(_ competitor: Competitor?, color: Color) -> some View {
        HStack(spacing: 7) {
            TeamLogo(urlString: competitor?.team?.logo,
                     teamAbbreviation: competitor?.team?.abbreviation, size: 22)
            Text(competitor?.team?.abbreviation ?? "—")
                .font(.system(size: 14, weight: .bold))
                .tracking(0.3)
                .foregroundStyle(color)
        }
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
            Text("Recent form")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.dsFgPrimary)
            formRow(event.homeCompetitor, color: matchColors.home.fill, form: preview.home)
            formRow(event.awayCompetitor, color: matchColors.away.fill, form: preview.away)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsBgCard)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 20)
    }

    private func formRow(_ competitor: Competitor?, color: Color, form: TeamSeasonForm) -> some View {
        HStack(spacing: 10) {
            crestAbbr(competitor, color: color)
            Spacer(minLength: 8)
            if form.recent.isEmpty {
                Text("No matches yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 5) {
                    ForEach(Array(form.recent.enumerated()), id: \.offset) { _, result in
                        FormBadge(result: formBadgeResult(result))
                    }
                }
            }
        }
    }

    private func formBadgeResult(_ result: MatchResult) -> FormBadge.Result {
        switch result {
        case .win:  return .win
        case .draw: return .draw
        case .loss: return .loss
        }
    }

    private func oneDecimal(_ v: Double) -> String { String(format: "%.1f", v) }

    // MARK: - Header (shared across all states)

    private var header: some View {
        VStack(spacing: 16) {
            // Competition label (non-NWSL only) — neutral tracked-caps pill, matching
            // the schedule card's label. NWSL omits it (redundant on the home league).
            if let label = competition.displayLabel { competitionPill(label) }

            // Scaled-up Card C: crest (hero) + ABBREVIATION + score on each side, the
            // temporal state in the center column between them. Two-team context →
            // crest + abbreviation in team color (never a full club name).
            HStack(alignment: .top, spacing: 8) {
                teamColumn(event.homeCompetitor, color: matchColors.home.fill)
                centerColumn
                teamColumn(event.awayCompetitor, color: matchColors.away.fill)
            }

            // Broadcast color chip + venue (+ attendance for past) — the same rail
            // as the schedule card, shown across every state.
            if hasCompactInfo { compactInfoRow }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
        // Bleed the wash up under the transparent nav bar so the header reads
        // edge-to-edge (the §0 "card grows into the page" full-bleed).
        .background(alignment: .top) {
            headerBackground.ignoresSafeArea(edges: .top)
        }
    }

    private var hasCompactInfo: Bool {
        event.venueName != nil || event.broadcastName != nil || attendanceText != nil
    }

    // Broadcast color chip + venue (+ attendance for a finished match) — the
    // schedule card's rail, scaled into the header.
    private var compactInfoRow: some View {
        HStack(spacing: 10) {
            if let channel = event.broadcastName {
                BroadcastChip(name: channel)
            }
            if let venue = event.venueName {
                Text(venue)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.dsFgSecondary)
                    .lineLimit(1)
            }
            if viewModel.temporalState == .past, let attendance = attendanceText {
                Circle().fill(Color.dsFgQuaternary).frame(width: 3, height: 3)
                Text("\(attendance) attending")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.dsFgSecondary)
                    .lineLimit(1)
            }
        }
    }

    private var attendanceText: String? {
        guard let attendance = viewModel.summary?.gameInfo?.attendance else { return nil }
        return NumberFormatter.localizedString(from: NSNumber(value: attendance), number: .decimal)
    }

    private var headerBackground: some View {
        // The design's navy header panel (vertical #14151C → #101117), with a
        // subtle left→right team-color wash on top so the colors read as identity
        // tint, not a vivid split.
        LinearGradient(
            stops: [
                .init(color: wash(matchColors.home), location: 0.0),
                .init(color: Color.black.opacity(0.18), location: 0.35),
                .init(color: Color.black.opacity(0.18), location: 0.65),
                .init(color: wash(matchColors.away), location: 1.0),
            ],
            startPoint: .leading, endPoint: .trailing
        )
        .background(
            LinearGradient(colors: [.dsMdPanel, .dsMdPanelBottom],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    private var liveIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.dsStateLive)
                .frame(width: 8, height: 8)
                .opacity(pulse ? 0.3 : 1)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
            Text("LIVE")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.dsStateLive)
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

    private func teamColumn(_ competitor: Competitor?, color: Color) -> some View {
        VStack(spacing: 8) {
            // The crest is the hero (§0): 72pt, bare/ring-free on the dark wash.
            TeamLogo(urlString: competitor?.team?.logo, teamAbbreviation: competitor?.team?.abbreviation, size: 72)
            // Abbreviation directly below the crest, in the team's color — the
            // two-team-context rule (crest + ABBREVIATION, never a full club name).
            Text(competitor?.team?.abbreviation ?? "—")
                .font(.system(size: 16, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize()
            // Score under each crest, on that team's side. A fixed band so a future
            // match (no score) keeps the same header height as past/live.
            ZStack {
                if showScores, let score = competitor?.score {
                    Text(score)
                        .font(.dsScore)
                        .foregroundStyle(Color.dsFgPrimary)
                }
            }
            .frame(height: 44)
        }
        .frame(maxWidth: .infinity)
    }

    // The center column carries the temporal state between the two crests.
    @ViewBuilder
    private var centerColumn: some View {
        VStack(spacing: 8) {
            switch viewModel.temporalState {
            case .live:
                liveIndicator
                if let clockLine {
                    Text(clockLine)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.dsStateClock)   // orange live clock
                        .multilineTextAlignment(.center)
                }
            case .past:
                Text("FULL TIME")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Color.dsStateFinal)
            case .future:
                Text("KICKOFF")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Color.dsStateKickoff)
                Text(kickoffTimeText)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.dsStateKickoff)
                if let date = dateHeadline {
                    Text(date)
                        .font(.caption)
                        .foregroundStyle(Color.dsFgSecondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(minWidth: 72)
        .padding(.top, 28)
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

    private func competitionPill(_ label: String) -> some View {
        Text(label.uppercased())
            .font(.system(size: 10.5, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(Color.dsFgSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.dsBgTertiary, in: Capsule())
    }

    // MARK: - Derived values

    private var showScores: Bool {
        event.statusState == "in" || event.statusState == "post"
    }

    private var homeTeamColorID: String? { viewModel.summary?.homeRoster?.team?.id ?? viewModel.summary?.homeBoxscore?.team?.id }
    private var awayTeamColorID: String? { viewModel.summary?.awayRoster?.team?.id ?? viewModel.summary?.awayBoxscore?.team?.id }

    private var homeColorAbbr: String? { viewModel.summary?.homeRoster?.team?.abbreviation ?? viewModel.summary?.homeBoxscore?.team?.abbreviation }
    private var awayColorAbbr: String? { viewModel.summary?.awayRoster?.team?.abbreviation ?? viewModel.summary?.awayBoxscore?.team?.abbreviation }

    /// Team color hexes: the design palette (by abbreviation) wins, then a
    /// TeamBrandColors id-override, then ESPN's summary color. Keeps a club the
    /// same color here as in Home/Coming Up (e.g. the Spirit's red, not gray).
    private var homeHex: String? { DesignTeamColors.hex(for: homeColorAbbr) ?? TeamBrandColors.primary(for: homeTeamColorID) ?? viewModel.summary?.homeRoster?.team?.color ?? viewModel.summary?.homeBoxscore?.team?.color }
    private var awayHex: String? { DesignTeamColors.hex(for: awayColorAbbr) ?? TeamBrandColors.primary(for: awayTeamColorID) ?? viewModel.summary?.awayRoster?.team?.color ?? viewModel.summary?.awayBoxscore?.team?.color }
    private var homeAltHex: String? { TeamBrandColors.alternate(for: homeTeamColorID) ?? viewModel.summary?.homeRoster?.team?.alternateColor ?? viewModel.summary?.homeBoxscore?.team?.alternateColor }
    private var awayAltHex: String? { TeamBrandColors.alternate(for: awayTeamColorID) ?? viewModel.summary?.awayRoster?.team?.alternateColor ?? viewModel.summary?.awayBoxscore?.team?.alternateColor }

    /// True once the summary has supplied at least one team color.
    private var hasTeamColors: Bool { homeHex != nil || awayHex != nil || homeAltHex != nil || awayAltHex != nil }

    /// Both teams' resolved colors for this match — each legible on dark and
    /// guaranteed distinct from the other. The single source for every side-by-side
    /// team-color callsite: formation dots, stat bars + values, the stats header,
    /// and the header wash/crest borders.
    private var matchColors: (home: ResolvedTeamColor, away: ResolvedTeamColor) {
        // Non-NWSL matches render each side by the schedule card's rule: a known side
        // (NWSL club, women's national team, or Champions Cup foreign club) keeps its
        // brand color; an unknown side goes NEUTRAL gray. NWSL matches use the full
        // summary-driven resolver (unchanged).
        if !competition.isNWSL {
            return (sideColor(event.homeCompetitor), sideColor(event.awayCompetitor))
        }
        return Color.resolveMatchColors(
            homePrimary: homeHex, homeAlt: homeAltHex,
            awayPrimary: awayHex, awayAlt: awayAltHex
        )
    }

    /// One side's color for a non-NWSL match: brand color if we know it (NWSL club,
    /// women's national team, or known Champions Cup foreign club), else neutral gray
    /// (mirrors MatchCard.teamColor).
    private func sideColor(_ competitor: Competitor?) -> ResolvedTeamColor {
        guard let hex = DesignTeamColors.displayHex(for: competitor?.team?.abbreviation) else {
            return ResolvedTeamColor(fill: Color(hex: "8E8E93"), onText: .white)
        }
        return ResolvedTeamColor(fill: Color.teamFillOnDark(hex: hex), onText: .white)
    }

    /// Header wash respects "no tint until the summary's colors arrive" (the resolver
    /// always returns a fallback, so gate on hasTeamColors) — but a non-NWSL match
    /// resolves its colors synchronously from the event, so it tints right away.
    private func wash(_ resolved: ResolvedTeamColor) -> Color {
        (hasTeamColors || !competition.isNWSL) ? resolved.fill.opacity(0.30) : .clear
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
