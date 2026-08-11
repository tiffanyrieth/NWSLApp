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
//             running clock; the data refreshes on a 60s poll (+ instantly when a
//             foreground V1 push arrives — see RootTabView's foregroundPushNonce).
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

import MatchClockKit
import SwiftUI

struct MatchDetailView: View {
    @State private var viewModel: MatchDetailViewModel
    /// The competition this match belongs to — drives the header competition pill,
    /// the info-row competition name, and neutral rendering of non-NWSL sides.
    /// Defaults to `.nwsl` so the 99% schedule path is unchanged.
    private let competition: CompetitionType

    /// NT match → the feed slug + label the tapped-player enrichment needs; nil on club matches.
    private var ntFeedLabel: String? {
        if case .international(let l) = competition { return l }
        return nil
    }
    private var ntFeedSlug: String? { ntFeedLabel.flatMap { NationalTeamFeed.slug(forLabel: $0) } }

    @Environment(MatchStore.self) private var matchStore
    @Environment(\.openURL) private var openURL
    /// Capped at AX1 app-wide (`RootTabView`), so this is true at exactly one size.
    @Environment(\.dynamicTypeSize) private var typeSize

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

    /// The live event snapshot powering the header + temporal state. Prefer the
    /// shared MatchStore's copy — the RootTabView live-poll keeps it fresh, so the
    /// header score/clock and the past→live→final transition ADVANCE while this
    /// screen is open (the seed event handed in at push is frozen). Falls back to
    /// that seed until the store has this id (or for a feed the store doesn't carry).
    private var event: Event {
        matchStore.events.first { $0.id == viewModel.event.id } ?? viewModel.event
    }

    /// Temporal state derived from the LIVE `event` above (not the VM's frozen seed),
    /// so a match that kicks off or finishes while open flips state without a relaunch.
    private var temporalState: MatchTemporalState {
        switch event.statusState {
        case "in":   return .live
        case "post": return .past
        default:     return .future
        }
    }

    var body: some View {
        Group {
            switch temporalState {
            case .past, .live: tabbedLayout
            case .future:      futureLayout
            }
        }
        .background(Color.dsBgPrimary)
        // Tapping a lineup-pitch player pushes her stat screen (same PlayerDetailView as Teams →
        // team → player). The pitch dots use a CLOSURE-based NavigationLink (see CombinedPitchView)
        // — a value + `navigationDestination(for:)` registered HERE was mis-scoped (MatchDetail is a
        // pushed child) and double-pushed the screen (2026-07-18 bug), so it lives on the dot now.
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
            // First load (shows a spinner), then poll the /summary tabs until the match
            // is final. We loop while NOT past (re-reading the LIVE temporal state each
            // tick) rather than only-while-live, so a screen opened before kickoff still
            // starts refreshing once the store flips it live — 60s live (owner call
            // 2026-07-16: the ≤30s surface is the V2 card; per-user polling scales against
            // the proxy request cap), slower pre-match.
            // The header score/clock advance separately via `event` (the refreshing store).
            if case .idle = viewModel.summaryState { await viewModel.loadSummary() }
            // Weather — fire alongside the summary, not gated on it (additive). Past → the
            // historical header stamp; future → the game-time forecast strip; live → no-op.
            // Pass the LIVE temporal state, not the VM's frozen seed.
            await viewModel.loadWeather(temporalState: temporalState)
            while !Task.isCancelled && temporalState != .past {
                let interval: Duration = temporalState == .live ? .seconds(60) : .seconds(120)
                try? await Task.sleep(for: interval)
                if Task.isCancelled { break }
                await viewModel.refresh()
            }
            // The poll loop only exits once the match is past — a match that finished while
            // on-screen now has historical weather available, so make one attempt after the loop.
            await viewModel.loadWeather(temporalState: temporalState)
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
    // segmented-control chrome (matches the mockup). Underline uses the match-state
    // accent: cyan (dsStateKickoff) for a past recap, orange (dsStateClock) while live.
    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(visibleTabs, id: \.self) { item in
                Button { tab = item } label: {
                    VStack(spacing: 6) {
                        Text(tabLabel(item).uppercased())
                            .dsFont(12, weight: .semibold)
                            .tracking(1)
                            .foregroundStyle(effectiveTab == item ? Color.dsFgPrimary : Color.dsFgSecondary)
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
                // Whole tab column tappable — .plain hit-tests only the centered label text otherwise,
                // leaving the rest of the equal-width column dead. (Tap-target audit.)
                .contentShape(Rectangle())
            }
        }
        .animation(.easeInOut(duration: 0.2), value: tab)
        .padding(.horizontal)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    private var underlineColor: Color {
        // Cyan for a past recap, orange while live (the design's state accents).
        temporalState == .live ? .dsStateClock : .dsStateKickoff
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

                if temporalState == .live {
                    Text("Updates every ~60 seconds")
                        .dsFont(13)
                        .foregroundStyle(Color.dsFgSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)
                        .padding(.bottom, 16)
                }
            }
            // Same structural guard as futureLayout: clamp to the viewport width so no over-wide
            // child (stat bars, long broadcast text, etc.) can make this vertical scroll pan sideways.
            .containerRelativeFrame(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.dsBgPrimary)
    }

    // MARK: - Summary tab (events timeline)

    @ViewBuilder
    private func summaryTab(_ summary: MatchSummary) -> some View {
        let homeID = summary.homeBoxscore?.team?.id ?? summary.homeRoster?.team?.id
        let homeName = summary.homeRoster?.team?.displayName ?? summary.homeBoxscore?.team?.displayName
        // The FULL play-by-play, newest-first (goals/cards/subs enriched from keyEvents +
        // shots/fouls/corners/offsides/VAR from commentary).
        let items = summary.playByPlay(homeID: homeID, homeDisplayName: homeName)
        // Crest + abbreviation per side for each event row's left color box.
        let homeCrest = event.homeCompetitor?.team?.logo
        let awayCrest = event.awayCompetitor?.team?.logo
        let homeAbbr = event.homeCompetitor?.team?.abbreviation ?? summary.homeRoster?.team?.abbreviation
        let awayAbbr = event.awayCompetitor?.team?.abbreviation ?? summary.awayRoster?.team?.abbreviation

        VStack(spacing: 14) {
            // Recap header: highlight clips deep-link out to ESPN. (Top performers is STATS, not
            // plays — it lives on the Stats tab, 2026-07-21.)
            if let videos = summary.videos, !videos.isEmpty { highlightsCard(videos) }

            if items.isEmpty {
                // A real match with no events yet says "No key events yet"; a truly sparse
                // fixture (no lineups, no stats either — common for a non-NWSL match) gets
                // the gentler "will be updated" copy.
                let hasRichData = summary.homeRoster != nil || summary.awayRoster != nil
                    || !statRows(summary).isEmpty
                emptyState(hasRichData ? "No key events yet."
                                       : "Match details will be updated when available.")
            } else {
                // Lazy — a full match's play-by-play is 100+ rows.
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        EventTimelineRow(
                            item: item,
                            minuteColor: underlineColor,
                            teamColor: item.isHome ? matchColors.home.fill : matchColors.away.fill,
                            crestURL: item.isHome ? homeCrest : awayCrest,
                            crestAbbr: item.isHome ? homeAbbr : awayAbbr
                        )
                        if item.id != items.last?.id { Divider().padding(.leading, 2) }
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.dsBgCard)
                .clipShape(RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous))
            }

            if let officials = officialsText(summary) {
                Text(officials)
                    .dsFont(13)
                    .foregroundStyle(Color.dsFgSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding()
    }

    /// Match highlight clips — a horizontal rail of thumbnails that DEEP-LINK OUT to ESPN's
    /// web player (no in-app playback: ESPN video = ads + auth, against values). Thumbnails load
    /// direct from ESPN's CDN via CachedThumbnail (not the proxy) — on-demand + cached.
    private func highlightsCard(_ videos: [MatchVideo]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Highlights")
                .dsFont(15, weight: .bold)
                .foregroundStyle(Color.dsFgPrimary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(videos.enumerated()), id: \.offset) { _, video in
                        highlightClip(video)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsBgCard)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous))
    }

    private func highlightClip(_ video: MatchVideo) -> some View {
        Button {
            if let url = video.webURL { openURL(url) }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    CachedThumbnail(url: video.thumbnailURL) {
                        Rectangle().fill(Color.dsMdCard)
                    }
                    .frame(width: 220, height: 124)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Image(systemName: "play.circle.fill")
                        .dsFont(34)
                        .foregroundStyle(.white.opacity(0.92))
                        .shadow(radius: 3)
                    if let duration = video.durationLabel {
                        Text(duration)
                            .dsFont(12, weight: .bold, monospacedDigit: true)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(.black.opacity(0.7), in: Capsule())
                            .padding(6)
                            .frame(width: 220, height: 124, alignment: .bottomTrailing)
                    }
                }
                .frame(width: 220, height: 124)
                Text(video.headline ?? "Highlight")
                    .dsFont(13, weight: .semibold)
                    .foregroundStyle(Color.dsFgPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(width: 220, height: 34, alignment: .topLeading)
                Label("Watch on ESPN", systemImage: "arrow.up.right")
                    .dsFont(13, weight: .semibold)
                    .foregroundStyle(Color.dsFgSecondary)
            }
        }
        .buttonStyle(.plain)
    }

    /// Per-match top performers — each category (Total Shots / Accurate Passes / Defensive
    /// Interventions / Saves) with each team's leader, home-left / away-right in team colors.
    private func topPerformersCard(_ rows: [TopPerformerRow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Top performers")
                .dsFont(15, weight: .bold)
                .foregroundStyle(Color.dsFgPrimary)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    HStack(spacing: 8) {
                        performerSide(row.home, color: matchColors.home.fill, trailing: false)
                        Text(row.category)
                            .dsFont(13, weight: .semibold)
                            .foregroundStyle(Color.dsFgSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity)
                        performerSide(row.away, color: matchColors.away.fill, trailing: true)
                    }
                    .padding(.vertical, 9)
                    if index < rows.count - 1 { Divider() }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsBgCard)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous))
    }

    @ViewBuilder
    private func performerSide(_ pick: LeaderPick?, color: Color, trailing: Bool) -> some View {
        if let pick {
            VStack(alignment: trailing ? .trailing : .leading, spacing: 1) {
                Text(pick.value)
                    .dsFont(16, weight: .heavy, design: .rounded, monospacedDigit: true)
                    .foregroundStyle(color)
                Text(pick.jersey.map { "\($0)  \(pick.name)" } ?? pick.name)
                    .dsFont(13)
                    .foregroundStyle(Color.dsFgSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
        } else {
            Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
        }
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
    // A FormationPitchView renders above the starters list for known formation
    // strings; this list rendering is the permanent fallback for unknown formations
    // (never a broken pitch).

    @ViewBuilder
    private func lineupsTab(_ summary: MatchSummary) -> some View {
        // Gate on ACTUAL players, not just the roster object: ESPN/the proxy can return
        // team-header "shells" (roster present, no players) — showing an honest empty
        // state beats a "STARTING XI" heading with nothing under it. (Diagnostic is
        // emitted in the VM on load; NO SILENT FAILURES.)
        let homePlayers = summary.homeRoster?.roster?.count ?? 0
        let awayPlayers = summary.awayRoster?.roster?.count ?? 0
        if homePlayers == 0 && awayPlayers == 0 {
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
        // A NATIONAL-TEAM match passes the feed slug instead of a club id: the "club" id here
        // is a country (Zambia = 20795) and 404s the NWSL roster route — the tapped-player view
        // uses the slug for competition-scoped bio + tournament stats instead.
        return CombinedPitchView.Side(
            abbr: roster.team?.abbreviation ?? "—",
            formation: roster.formation,
            players: roster.starters,
            accent: accent,
            clubID: ntFeedSlug == nil ? roster.team?.id : nil,
            leagueSlug: ntFeedSlug,
            competitionLabel: ntFeedSlug == nil ? nil : ntFeedLabel
        )
    }

    private func combinedPitchCard(_ home: MatchRoster, _ away: MatchRoster) -> some View {
        CombinedPitchView(home: side(home, matchColors.home), away: side(away, matchColors.away))
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.dsBgCard)
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous))
    }

    private func substitutesCard(_ roster: MatchRoster) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // "BENCH" — the unused/used substitutes. ("Substitutes" was a mislabel for
            // a finished match: it's the bench, not who came on.)
            Text("\((roster.team?.displayName ?? roster.team?.abbreviation ?? "—").uppercased()) BENCH")
                .dsFont(12, weight: .semibold)
                .tracking(0.5)
                .foregroundStyle(Color.dsFgSecondary)
            FlowLayout(spacing: 8) {
                ForEach(Array(roster.substitutes.enumerated()), id: \.offset) { _, player in
                    substituteChip(player, roster: roster)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsBgCard)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous))
    }

    private func rosterBlock(_ roster: MatchRoster) -> some View {
        let accent = roster.homeAway == "away" ? matchColors.away : matchColors.home
        return VStack(alignment: .leading, spacing: 12) {
            // One centered, uppercased line: "WASHINGTON SPIRIT — 4-2-3-1".
            Text(formationHeader(roster))
                .dsFont(12, weight: .semibold)
                .tracking(0.5)
                .foregroundStyle(Color.dsFgSecondary)
                .frame(maxWidth: .infinity, alignment: .center)

            // Pitch when we can place all 11 by position; the list is the
            // permanent fallback (never a broken pitch).
            if FormationPitchView.supports(formation: roster.formation, players: roster.starters) {
                FormationPitchView(
                    formation: roster.formation,
                    players: roster.starters,
                    accent: accent,
                    abbr: roster.team?.abbreviation,
                    clubID: ntFeedSlug == nil ? roster.team?.id : nil,
                    leagueSlug: ntFeedSlug,
                    competitionLabel: ntFeedSlug == nil ? nil : ntFeedLabel
                )
            } else {
                lineupList("Starting XI", players: roster.starters)
            }

            if !roster.substitutes.isEmpty {
                substituteChips(roster)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsBgCard)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous))
    }

    private func formationHeader(_ roster: MatchRoster) -> String {
        let team = (roster.team?.displayName ?? "—").uppercased()
        if let formation = roster.formation { return "\(team) — \(formation)" }
        return team
    }

    // Compact wrapping chips: "18 MacIver  14 Carle 61'". The minute shows for a
    // player who came on. Reuses FlowLayout so they wrap across lines.
    private func substituteChips(_ roster: MatchRoster) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BENCH")
                .dsFont(12, weight: .semibold)
                .tracking(0.5)
                .foregroundStyle(Color.dsFgSecondary)
            FlowLayout(spacing: 8) {
                ForEach(Array(roster.substitutes.enumerated()), id: \.offset) { _, player in
                    substituteChip(player, roster: roster)
                }
            }
        }
    }

    /// One bench player. Tappable through to her player page — you look at the bench precisely
    /// BECAUSE you're wondering about someone who isn't on the pitch, so the starters being the
    /// only tappable names was backwards. Uses the same closure-based NavigationLink as the pitch
    /// dots (see CombinedPitchView.playerDot for why a value-based destination breaks here), and
    /// degrades to a plain chip when ESPN gave no athlete id — there'd be nothing to open.
    @ViewBuilder
    private func substituteChip(_ player: MatchPlayer, roster: MatchRoster) -> some View {
        if let athlete = player.asAthlete {
            NavigationLink {
                LineupPlayerStatsView(ref: LineupPlayerRef(
                    athlete: athlete,
                    // A national-team "club" id is a country and 404s the NWSL roster route;
                    // the feed slug drives competition-scoped bio + tournament stats instead.
                    clubID: ntFeedSlug == nil ? roster.team?.id : nil,
                    accentHex: DesignTeamColors.hex(for: roster.team?.abbreviation ?? ""),
                    leagueSlug: ntFeedSlug,
                    competitionLabel: ntFeedSlug == nil ? nil : ntFeedLabel
                ))
            } label: {
                substituteChipLabel(player)
            }
            .buttonStyle(.plain)
        } else {
            substituteChipLabel(player)
        }
    }

    /// ⚠️ Sizing is deliberate, not incidental. At 11pt the name was borderline and the sub-in
    /// marker — a 9pt glyph at 80% opacity — read on a real phone as an unidentifiable green
    /// dot, so the one thing the chip exists to tell you (SHE CAME ON) was the least legible
    /// part of it. Owner call 2026-07-31: the bench should sit at roughly what AX1 was showing.
    /// The arrow now matches the text size and runs at full strength.
    private func substituteChipLabel(_ player: MatchPlayer) -> some View {
        HStack(spacing: 5) {
            Text(player.jersey ?? "–")
                .dsFont(14, weight: .bold)
                .monospacedDigit()
                .foregroundStyle(Color.dsFgSecondary)
            Text(subLastName(player))
                .dsFont(15)
                .foregroundStyle(Color.dsFgPrimary)
            if player.didSubIn {
                Image(systemName: "arrow.up.circle.fill")
                    .dsFont(15)
                    .foregroundStyle(Color.dsSuccess)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(Color.dsBgTertiary, in: Capsule())
        // One node per player for VoiceOver, with the sub-in stated rather than left to a glyph.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(player.jersey.map { "Number \($0), " } ?? "")\(subLastName(player))"
                + (player.didSubIn ? ", came on as a substitute" : "")
        )
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
                .dsFont(12, weight: .semibold)
                .tracking(0.5)
                .foregroundStyle(Color.dsFgSecondary)
            ForEach(Array(players.enumerated()), id: \.offset) { _, player in
                HStack(spacing: 10) {
                    Text(player.jersey ?? "–")
                        .dsFont(12, weight: .bold)
                        .monospacedDigit()
                        .foregroundStyle(Color.dsFgSecondary)
                        .frame(width: 24, alignment: .trailing)
                    Text(player.athlete?.displayName ?? "—")
                        .dsFont(16)
                    if player.didSubOut {
                        Image(systemName: "arrow.down.circle.fill")
                            .dsFont(13)
                            .foregroundStyle(.red.opacity(0.7))
                    }
                    if player.didSubIn {
                        Image(systemName: "arrow.up.circle.fill")
                            .dsFont(13)
                            .foregroundStyle(.green.opacity(0.7))
                    }
                    Spacer(minLength: 0)
                    if let pos = player.position?.abbreviation {
                        Text(pos)
                            .dsFont(13)
                            .foregroundStyle(Color.dsFgSecondary)
                    }
                }
            }
        }
    }

    // MARK: - Stats tab (head-to-head comparison bars)

    @ViewBuilder
    private func statsTab(_ summary: MatchSummary) -> some View {
        let homeID = summary.homeBoxscore?.team?.id ?? summary.homeRoster?.team?.id
        let performers = summary.topPerformers(homeID: homeID)
        let rows = statRows(summary)
        if performers.isEmpty && rows.isEmpty {
            emptyState("Match stats aren't available.")
        } else {
            VStack(spacing: 16) {
                // Per-team leaders first (moved here from Play-by-Play — it's stats, not plays).
                if !performers.isEmpty { topPerformersCard(performers) }
                if !rows.isEmpty { teamComparisonCard(summary, rows: rows) }
            }
            .padding()
        }
    }

    /// The head-to-head comparison bars for the whole-team boxscore stats.
    private func teamComparisonCard(_ summary: MatchSummary, rows: [StatRow]) -> some View {
        VStack(spacing: 16) {
            // Team-abbreviation header anchors which side is which, in color.
            HStack {
                Text(summary.homeBoxscore?.team?.abbreviation ?? "—")
                    .foregroundStyle(matchColors.home.fill)
                Spacer()
                Text(summary.awayBoxscore?.team?.abbreviation ?? "—")
                    .foregroundStyle(matchColors.away.fill)
            }
            .dsFont(13, weight: .bold)

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
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous))
    }

    /// The stats we surface, in display order. `percent` stats are normalized so
    /// "0.9" (pass accuracy) and "61" (possession) both read as a percentage. A spec
    /// with no data on BOTH sides drops out (statRows), so a sparse match stays clean.
    private struct StatSpec { let name: String; let label: String; let percent: Bool }
    private static let statSpecs: [StatSpec] = [
        .init(name: "possessionPct",  label: "Possession",      percent: true),
        .init(name: "totalShots",     label: "Shots",           percent: false),
        .init(name: "shotsOnTarget",  label: "Shots on Target", percent: false),
        .init(name: "wonCorners",     label: "Corners",         percent: false),
        .init(name: "saves",          label: "Saves",           percent: false),
        .init(name: "totalPasses",    label: "Passes",          percent: false),
        .init(name: "passPct",        label: "Pass Accuracy",   percent: true),
        .init(name: "totalCrosses",   label: "Crosses",         percent: false),
        .init(name: "totalLongBalls", label: "Long Balls",      percent: false),
        .init(name: "totalTackles",   label: "Tackles",         percent: false),
        .init(name: "interceptions",  label: "Interceptions",   percent: false),
        .init(name: "effectiveClearance", label: "Clearances",  percent: false),
        .init(name: "blockedShots",   label: "Blocks",          percent: false),
        .init(name: "foulsCommitted", label: "Fouls",           percent: false),
        .init(name: "offsides",       label: "Offsides",        percent: false),
        .init(name: "yellowCards",    label: "Yellow Cards",    percent: false),
        .init(name: "redCards",       label: "Red Cards",       percent: false),
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
            // Drop a row that's 0 on BOTH sides (e.g. red cards, offsides in a clean game) — a
            // 0–0 bar conveys nothing and reads as empty. A one-sided value (saves 6–0) stays.
            if h == 0 && a == 0 { return nil }
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
        // Header OUTSIDE the ScrollView — exactly like tabbedLayout — so its full-bleed
        // background reaches the top edge under the status bar. Inside a ScrollView the top
        // safe area clips it, leaving a black gap (the "doesn't fully expand" bug, image 8).
        return VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 24) {
                    HowToWatchCard(broadcast: broadcastName)
                        .padding(.horizontal, 20)
                    preMatchLineups
                    if preview.hasData {
                        seasonComparison(preview)
                        recentForm(preview)
                    }
                    // OUTSIDE the `preview.hasData` block on purpose — an early-season match with no
                    // season/form data must still get its weather. Renders only with a full forecast
                    // window (isForecast); unavailable/indoor/too-far-out → no card, honest absence.
                    gameTimeWeather
                }
                .padding(.top, 24)      // preserve the old header→grid gap now that header is pinned
                .padding(.bottom, 20)
                // Structural guard: clamp the content to the scroll viewport's width so no single
                // over-wide child can make this VERTICAL scroll view drift/pan horizontally (a recurring
                // class — the kickoff-time text hit it once, then a future-game layout again, 2026-07-11).
                // Flexible children fit; anything genuinely over-wide clips instead of enabling a 2D drag.
                .containerRelativeFrame(.horizontal)
            }
        }
    }

    // ⚠️ The Venue / Broadcast / Competition tile row was REMOVED (2026-08-03, owner). Every field it
    // held was already shown elsewhere: venue + broadcast on the header's `compactInfoRow` (and the
    // broadcast again, richer, on the How-to-watch card), and the competition on the SCHEDULE card the
    // user tapped to get here (shown only for non-regular-season). The tiles duplicated all of it,
    // cramped the venue into a truncating third-width, and added three floating modules to a screen
    // already fighting a boxy feel. OPEN (pending a Design call): re-add a competition label to the
    // header for NON-regular-season matches only, so a Champions Cup / playoff match reached from Home
    // (not the schedule) still shows its competition. Regular-season match details stay clean.

    /// Pre-kickoff starting XIs, shown once ESPN posts them (~1h before kickoff — the future detail's
    /// 120s `/summary` poll + the proxy's lineup-window TTL surface them). Reuses the exact live/past
    /// lineups rendering (`lineupsTab`). Hidden entirely until real players arrive, so a pre-publish
    /// future match shows no empty card.
    @ViewBuilder
    private var preMatchLineups: some View {
        if let summary = viewModel.summary,
           summary.homeRoster?.roster?.isEmpty == false || summary.awayRoster?.roster?.isEmpty == false {
            VStack(alignment: .leading, spacing: 12) {
                Text("Starting lineups")
                    .dsFont(17, weight: .bold)
                    .foregroundStyle(Color.dsFgPrimary)
                    .padding(.horizontal, 20)
                lineupsTab(summary)
            }
        }
    }

    private func seasonComparison(_ preview: MatchPreview) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Season comparison")
                .dsFont(17, weight: .bold)
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
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous))
        .padding(.horizontal, 20)
    }

    /// Crest + abbreviation in the team's color — the two-team-context identity
    /// (CLAUDE.md: never full club names, never crest-less text in a matchup).
    private func crestAbbr(_ competitor: Competitor?, color: Color) -> some View {
        HStack(spacing: 7) {
            TeamLogo(urlString: competitor?.team?.logo,
                     teamAbbreviation: competitor?.team?.abbreviation, size: 22)
            Text(competitor?.team?.abbreviation ?? "—")
                .dsFont(14, weight: .bold)
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
                .dsFont(17, weight: .bold)
                .foregroundStyle(Color.dsFgPrimary)
            formRow(event.homeCompetitor, color: matchColors.home.fill, form: preview.home)
            formRow(event.awayCompetitor, color: matchColors.away.fill, form: preview.away)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsBgCard)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous))
        .padding(.horizontal, 20)
    }

    private func formRow(_ competitor: Competitor?, color: Color, form: TeamSeasonForm) -> some View {
        HStack(spacing: 10) {
            crestAbbr(competitor, color: color)
            Spacer(minLength: 8)
            if form.recent.isEmpty {
                Text("No matches yet")
                    .dsFont(13)
                    .foregroundStyle(Color.dsFgSecondary)
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
            // as the schedule card — with the past-match kickoff weather as a quiet
            // centered line beneath it.
            if hasCompactInfo {
                VStack(spacing: 5) {
                    compactInfoRow
                    weatherStamp
                }
            }
            spanishBroadcastRow
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        // Bleed the wash up under the transparent nav bar so the header reads
        // edge-to-edge (the §0 "card grows into the page" full-bleed).
        .background(alignment: .top) {
            headerBackground.ignoresSafeArea(edges: .top)
        }
    }

    // Resolved primary channel — curated English home for comps ESPN only carries
    // in Spanish (Champions Cup → Paramount+), else ESPN's own value.
    private var broadcastName: String? {
        competition.primaryBroadcastOverride ?? event.broadcastName
    }

    private var hasCompactInfo: Bool {
        event.venueName != nil || broadcastName != nil || showsAttendanceLine
            || viewModel.weather?.roundedTemp != nil
    }

    /// One predicate for BOTH the rail gate (`hasCompactInfo`) and `attendanceLine` itself, so the
    /// bare "Attendance:" label (the deliberate number-arrives-later affordance) can never be
    /// rendered by one gate and suppressed by the other. Shows once the match is over and we have
    /// either a figure (from either source) or a loaded summary record awaiting its count.
    private var showsAttendanceLine: Bool {
        temporalState == .past && (attendanceText != nil || viewModel.summary?.gameInfo != nil)
    }

    // Broadcast color chip + venue (+ attendance for a finished match) — the
    // schedule card's rail, scaled into the header.
    /// ⚠️ Wraps to two lines rather than truncating, because at AX1 this rail could not fit
    /// broadcast + venue + attendance on one line and `lineLimit(1)` ate the crowd figure
    /// outright — "Attendance:…" with the number gone (caught by the AX1 pass, 2026-07-31).
    /// A truncated venue is a cosmetic loss; a silently dropped number is the AX1 gate failing.
    /// `ViewThatFits` keeps the single-line rail at every normal size and only stacks when it
    /// genuinely doesn't fit, so nothing changes for the 99% case.
    private var compactInfoRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                broadcastAndVenue
                attendanceLine
            }
            VStack(spacing: 4) {
                HStack(spacing: 10) { broadcastAndVenue }
                attendanceLine
            }
        }
    }

    @ViewBuilder
    private var broadcastAndVenue: some View {
        if let channel = broadcastName {
            BroadcastChip(name: channel)
        }
        if let venue = event.venueName {
            Text(venue)
                .dsFont(13)
                .foregroundStyle(Color.dsFgSecondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var attendanceLine: some View {
        if showsAttendanceLine {
            HStack(spacing: 10) {
                Circle().fill(Color.dsFgQuaternary).frame(width: 3, height: 3)
                // Label with no number when the count hasn't landed — see attendanceText.
                Text(attendanceText.map { "Attendance: \($0)" } ?? "Attendance:")
                    .dsFont(13)
                    .foregroundStyle(Color.dsFgSecondary)
                    .lineLimit(1)
            }
        }
    }

    // Historical kickoff weather (past matches only) — a quiet centered line UNDER the
    // metadata row, not crowded into it. Concatenating Text(Image) + Text keeps the SF
    // Symbol on the same @ScaledMetric .dsFont axis as the temperature so Dynamic Type
    // scales the icon and number together; dsFgTertiary reads a step quieter than the row.
    @ViewBuilder
    private var weatherStamp: some View {
        if temporalState == .past, let weather = viewModel.weather, let temp = weather.roundedTemp {
            (Text(Image(systemName: weather.symbolName)) + Text(" \(temp)°"))
                .dsFont(13)
                .foregroundStyle(Color.dsFgSecondary)
                .lineLimit(1)
                .accessibilityLabel(weather.accessibilityLabel)
        }
    }

    // Game-time weather strip (future matches only) — the forecast for the 4-hour game window.
    // Gated on `isForecast` (a full 4-hour window); anything else (unavailable / indoor /
    // >10-days-out / no window) simply omits the card. Kickoff comes from the live `event`.
    @ViewBuilder
    private var gameTimeWeather: some View {
        if temporalState == .future, let weather = viewModel.weather, weather.isForecast,
           let hours = weather.hours, let kickoff = event.kickoff {
            GameTimeWeatherCard(hours: hours, venueName: weather.venueName,
                                sunset: weather.sunsetDate, kickoff: kickoff)
                .padding(.horizontal, 20)
        }
    }

    // Spanish-language secondary, shown only where ESPN's feed IS the Spanish feed
    // (Champions Cup) so the curated Paramount+ primary doesn't erase the real
    // Spanish option. Data-driven from ESPN's listed channels, so it self-corrects.
    // Lives in the header (not the future-only How-to-Watch card) so it's visible on
    // finished matches too.
    @ViewBuilder
    private var spanishBroadcastRow: some View {
        if competition.surfacesSpanishSecondary, !event.broadcastNames.isEmpty {
            Text("Español · \(event.broadcastNames.joined(separator: " · "))")
                .dsFont(13)
                .foregroundStyle(Color.dsFgSecondary)
                .lineLimit(1)
        }
    }

    /// The formatted crowd figure, or nil when there isn't one yet.
    ///
    /// ⚠️ **Zero is ESPN's "unknown", not a real crowd** — and we printed it verbatim as
    /// "Attendance: 0", which is simply false. Two different causes, indistinguishable in the
    /// payload: a count that lands hours-to-days after full time (some venues report late — GFC
    /// @ BAY was still 0 two days on, 2026-07-31), and matches where it will never exist at all
    /// (most national-team fixtures). Since we can't tell them apart, the label stays and only
    /// the number waits — so a late figure appearing later reads as the count arriving rather
    /// than the screen changing shape.
    ///
    /// **Scoreboard first, summary fallback (2026-08-09).** The scoreboard's
    /// `competitions[0].attendance` rides the live poll and self-heals, while the `/summary`
    /// copy can sit behind a long edge-cache TTL and read 0 for hours after FT (the
    /// frozen-attendance regression). `Event.attendance` already nils out ESPN's zero.
    private var attendanceText: String? {
        guard let attendance = event.attendance
            ?? viewModel.summary?.gameInfo?.attendance.flatMap({ $0 > 0 ? $0 : nil })
        else { return nil }
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
                .dsFont(13, weight: .bold)
                .foregroundStyle(Color.dsStateLive)
        }
        .onAppear { pulse = true }
    }

    /// "63:18 — Second Half": ESPN's last-fetched running clock + the period name.
    /// Fallback for when we can't tick locally (no raw `clock`/anchor).
    private var clockLine: String? {
        let clock = event.status?.displayClock
        let period = event.status?.type?.description
        let parts = [clock, period].compactMap { ($0?.isEmpty == false) ? $0 : nil }
        return parts.isEmpty ? nil : parts.joined(separator: " — ")
    }

    /// The live clock: a locally-ticking football minute ("51' — Second Half") anchored to
    /// the last fetch, so it advances smoothly between the ~60s polls. Falls back to ESPN's
    /// static `clockLine` when the raw clock/anchor aren't available.
    @ViewBuilder
    private var liveClockLine: some View {
        let periodName = event.status?.type?.description
        let suffix = (periodName?.isEmpty == false) ? " — \(periodName!)" : ""
        // The halftime / anchor / fallback decision lives once in MatchClockKit (halftime shows a
        // static "Halftime", never a ticking 45'+n' through the break — the V2 widget shows a static
        // HT and the app must match; the period-name suffix rides only the ticking minute).
        LiveMatchClockView(
            display: .resolve(
                statusState: event.statusState, isHalftime: event.isHalftime,
                clockSeconds: event.status?.clock, period: event.status?.period,
                anchor: matchStore.tickAnchor(for: event.id),
                halftimeLabel: "Halftime", fallback: clockLine),
            suffix: suffix
        ) { label in
            Text(label)
                .dsFont(15, weight: .medium)
                .foregroundStyle(Color.dsStateClock)   // orange live clock
                .multilineTextAlignment(.center)
        }
    }

    private func teamColumn(_ competitor: Competitor?, color: Color) -> some View {
        VStack(spacing: 8) {
            // The crest is the hero (§0): 72pt, bare/ring-free on the dark wash.
            TeamLogo(urlString: competitor?.team?.logo, teamAbbreviation: competitor?.team?.abbreviation, size: 72)
            // Abbreviation directly below the crest, in the team's color — the
            // two-team-context rule (crest + ABBREVIATION, never a full club name).
            Text(competitor?.team?.abbreviation ?? "—")
                .dsFont(16, weight: .bold)
                .tracking(0.5)
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize()
            // Score under each crest, on that team's side. A fixed band so a future
            // match (no score) keeps the same header height as past/live.
            ZStack {
                if showScores, let score = competitor?.score {
                    Text(score)
                        .dsScoreFont()
                        .foregroundStyle(Color.dsFgPrimary)
                }
            }
            // minHeight (not a fixed height) so the score band keeps a consistent
            // baseline at default text but can grow with the scaled score at larger sizes.
            .frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity)
    }

    // The center column carries the temporal state between the two crests.
    @ViewBuilder
    private var centerColumn: some View {
        VStack(spacing: 8) {
            switch temporalState {
            case .live:
                liveIndicator
                liveClockLine
            case .past:
                Text("FULL TIME")
                    .dsFont(12, weight: .bold)
                    .tracking(0.6)
                    .foregroundStyle(Color.dsStateFinal)
            case .future:
                Text("KICKOFF")
                    .dsFont(12, weight: .bold)
                    .tracking(0.6)
                    .foregroundStyle(Color.dsStateKickoff)
                Text(kickoffTimeText)
                    .dsFont(28, weight: .bold, design: .rounded, monospacedDigit: true)
                    .foregroundStyle(Color.dsStateKickoff)
                    // Keep the time on ONE line and let it scale down to fit the squeezed
                    // center column. Without this the 28pt "10:00 PM" (double-digit hours)
                    // both wrapped the "M" to a second line AND, being a rigid full-width
                    // Text, pushed the header past the viewport → horizontal drift. A
                    // minimumScaleFactor makes its width flexible, fixing both.
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if let date = dateHeadline {
                    Text(date)
                        .dsFont(13)
                        .foregroundStyle(Color.dsFgSecondary)
                        .multilineTextAlignment(.center)
                        // Wrap rather than truncate. This center column is squeezed between two
                        // crests (which must NOT shrink — §0), so at AX1 "Friday, July 31" was
                        // cut to "Friday, July…" — losing the date on a screen whose whole job is
                        // telling you when the match is. Two centered lines cost nothing here.
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(minWidth: 72)
        .padding(.top, 28)
    }

    // MARK: - Small shared pieces

    private func summaryError(_ message: String) -> some View {
        RetryStateView(message: message, style: .inline) {
            await viewModel.loadSummary()
        }
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .dsFont(16)
            .foregroundStyle(Color.dsFgSecondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
    }

    private func competitionPill(_ label: String) -> some View {
        Text(label.uppercased())
            .dsFont(12, weight: .bold)
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
        ResolvedTeamColor(fill: Color.teamColor(for: competitor), onText: .white)
    }

    /// Header wash respects "no tint until the summary's colors arrive" (the resolver
    /// always returns a fallback, so gate on hasTeamColors) — but a non-NWSL match
    /// resolves its colors synchronously from the event, so it tints right away.
    private func wash(_ resolved: ResolvedTeamColor) -> Color {
        (hasTeamColors || !competition.isNWSL) ? resolved.fill.opacity(0.30) : .clear
    }

    private static let dateHeadlineFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = .current; f.timeZone = .current; f.dateFormat = "EEEE, MMMM d"; return f
    }()
    private var dateHeadline: String? {
        guard let kickoff = event.kickoff else { return nil }
        return Self.dateHeadlineFormatter.string(from: kickoff)
    }

    private static let kickoffTimeFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = .current; f.timeZone = .current
        f.timeStyle = .short; f.dateStyle = .none; return f
    }()
    private var kickoffTimeText: String {
        guard let kickoff = event.kickoff else { return "TBD" }
        return Self.kickoffTimeFormatter.string(from: kickoff)
    }

}
