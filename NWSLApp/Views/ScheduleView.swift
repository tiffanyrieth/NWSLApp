//
//  ScheduleView.swift
//  NWSLApp
//
//  Full-season NWSL schedule as a vertical scroll of game cards (MLS-app
//  style), grouped under sticky local-day headers. On first successful load it
//  scrolls to today's section (or the next upcoming matchday if today has no
//  matches) so fans land on what's relevant instead of the season opener.
//
//  Three always-visible filter tabs sit below the title (per the schedule
//  design spec): NWSL (default) · My teams · All matches — three functions over
//  the same MatchStore data, no extra fetch for the season. Switching a filter
//  re-anchors the scroll to that filter's next upcoming match.
//
//  Layout note: this is a ScrollView + LazyVStack rather than a List. That gives
//  full control over card spacing (the crisp feel) and — crucially — unlocks iOS
//  17's `.scrollPosition(id:)`, which lets the schedule open already scrolled to the
//  initial-scroll section (seamless, no jump-down from the season opener).
//
//  Design rules honored:
//   #1 — no persistent overlays obscuring content (the filter control + nav
//        title are standard chrome above the scroll; status lives inside cards;
//        content respects safe-area insets).
//   #2 — NavigationStack is in place so future detail pushes are reversible.
//

import SwiftUI

struct ScheduleView: View {
    @State private var viewModel = ScheduleViewModel()
    // The season's events live in the shared store (injected in RootTabView);
    // this screen reads its slice through the view model.
    @Environment(MatchStore.self) private var matchStore
    // The shared club directory, for the "My teams" filter (resolves followed IDs
    // → abbreviations) and its error/retry path.
    @Environment(ClubStore.self) private var clubStore
    // The personalization lens, for the "My teams" filter + its empty prompt.
    @Environment(FollowingStore.self) private var following
    // For the tap-the-active-tab → scroll-to-today behavior (re-tap signal).
    @Environment(AppRouter.self) private var router
    // The postseason state (bracket / windows / clinch) — the playoffs live HERE (owner
    // decision: the bracket IS the schedule; Standings stays the pure table).
    @Environment(PlayoffStore.self) private var playoffs

    // Which filter tab is selected. Defaults to NWSL (the full league) so fans
    // can discover other games — NOT "My teams" (see the spec).
    @State private var selectedFilter: ScheduleViewModel.Filter = .nwsl

    // Drives the seamless first-open landing. The match list stays hidden (opacity 0)
    // until it's been scrolled to the rest boundary (the last kicked-off game's card
    // at the top), then revealed — so the schedule OPENS already positioned, with no
    // visible "load at March, then scroll down" (the old flash). Flips true once, on
    // the list's first appearance; re-anchors after that (filter change, re-tapping
    // the tab) animate, which is the intended behavior.
    @State private var hasPositioned = false

    // Push-tap deep link (consumes AppRouter.pendingMatchEventID): the resolved match to
    // push + the binding navigationDestination drives. Event isn't Hashable, so the
    // isPresented variant (not item:) is the mechanism.
    @State private var pushedMatch: ScheduledMatch?
    @State private var isShowingPushedMatch = false

    var body: some View {
        NavigationStack {
            // A custom large-title header (title + filter chips) pinned via
            // safeAreaInset, with the system nav bar hidden. The system large title
            // can't be used here: the screen auto-scrolls to today on open, which
            // immediately collapses it to the small inline title. The custom header
            // stays at full size and keeps the chips sticky above the scroll.
            content
                .toolbar(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .top, spacing: 0) { scheduleHeader }
                // The pushed-match destination lives at the NavigationStack level (NOT inside
                // the match list) so a tap on the Playoffs chip — a separate scroll view —
                // still pushes. A push-notification deep link also resolves from any chip.
                .navigationDestination(isPresented: $isShowingPushedMatch) {
                    if let pushedMatch {
                        MatchDetailView(event: pushedMatch.event, competition: pushedMatch.competition)
                    }
                }
                .onChange(of: router.pendingMatchEventID) { _, _ in consumePendingMatch() }
                .onChange(of: matchStore.lastLoadedAt) { _, _ in consumePendingMatch() }
                .onAppear { consumePendingMatch() }
        }
        // Hand the view model the shared store + following lens, then load on
        // first appearance. Gate ONLY the season on `.idle` (so re-selecting the
        // tab — or another screen, e.g. Home, having loaded the store first —
        // doesn't refetch ~240 events). The club directory is fetched separately
        // and unconditionally: it's independent of the season, internally guarded
        // (`clubs.isEmpty`), and the "My teams" filter needs it even when the
        // store was already loaded elsewhere.
        .task {
            viewModel.store = matchStore
            viewModel.clubStore = clubStore
            viewModel.following = following
            viewModel.playoffs = playoffs
            if case .idle = matchStore.state { await matchStore.load() }
            if case .idle = clubStore.state { await clubStore.load() }
            await refreshPlayoffs()
        }
        // Re-derive the postseason state whenever the season data changes (live advancement).
        .onChange(of: matchStore.lastLoadedAt) { _, _ in Task { await refreshPlayoffs() } }
        // The Playoffs chip retires (postseason rolled over / sim off) → fall back to NWSL.
        .onChange(of: playoffs.isChipVisible) { _, visible in
            if !visible, selectedFilter == .playoffs { selectedFilter = .nwsl }
        }
        // First-open positioning + all re-anchors live INSIDE the ScrollViewReader
        // (matchList) so they can drive the scroll proxy directly. See `matchList`.
    }

    /// Feed the derived-postseason store the loaded NWSL season (or, in DEBUG, the simulator).
    private func refreshPlayoffs() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-simulatePostseason2025") {
            playoffs.simulatePostseason2025(stage: PostseasonSimulator.Stage(arg: launchArg("-simulatePostseason2025Stage")))
            if launchArg("-simulatePostseasonSegment")?.lowercased() == "playoffs" {
                selectedFilter = .playoffs
            }
            return
        }
        #endif
        await playoffs.sync(nwslEvents: matchStore.nwslEvents)
    }

    #if DEBUG
    private func launchArg(_ name: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        let next = args[i + 1]
        return next.hasPrefix("-") ? nil : next
    }
    #endif


    // Large "Schedule" title + the filter chips, drawn as one pinned header.
    private var scheduleHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Schedule")
                .dsFont(32, weight: .bold)
                .foregroundStyle(Color.dsFgPrimary)
                .padding(.horizontal, 16)
                .padding(.top, 4)
            filterPicker
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsBgGrouped)
    }

    // The filter chips: NWSL · My teams, + "Playoffs" once 2+ teams have mathematically
    // clinched (or the bracket is seeded) — visibility is the view model's `visibleFilters`.
    private var filterPicker: some View {
        HStack(spacing: 8) {
            ForEach(viewModel.visibleFilters) { filter in
                Chip(label: filter.title, isActive: selectedFilter == filter, compact: true) {
                    selectedFilter = filter
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("Loading schedule…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let message):
            errorView(message) { await viewModel.load() }
        case .loaded:
            loadedContent
        }
    }

    // The loaded body depends on the filter — "My teams" has its own empty
    // states (no follows yet, or follows still resolving); "Playoffs" shows the
    // my-path-to-the-playoffs experience instead of the match list.
    @ViewBuilder
    private var loadedContent: some View {
        if selectedFilter == .playoffs {
            playoffsContent
        } else if selectedFilter == .myTeams && following.followedIDs.isEmpty
            && following.followedNationalTeams.isEmpty {
            // "My teams" is empty only when NOTHING is followed — clubs OR national
            // teams. (Following just a national team still fills this view.)
            followPrompt
        } else if selectedFilter == .myTeams && viewModel.isResolvingFollowedTeams {
            ProgressView("Loading your teams…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if selectedFilter == .myTeams, let clubsError = viewModel.clubsError {
            // The club directory (needed to resolve My-teams) failed to load.
            // Show a real error + retry instead of a misleading "No matches" (#16).
            errorView(clubsError) { await clubStore.load() }
        } else {
            let sections = viewModel.scheduleSections(for: selectedFilter)
            if sections.isEmpty {
                emptyState
            } else {
                matchList(sections)
            }
        }
    }

    // MARK: - Playoffs chip content ("my path to the playoffs")

    /// Clinch window (chip visible, bracket unseeded): per-followed-team status + the TBD
    /// rounds. Seeded: the full bracket road (PlayoffPathView).
    @ViewBuilder
    private var playoffsContent: some View {
        ScrollView {
            if let bracket = playoffs.bracket {
                PlayoffPathView(bracket: bracket, onOpenMatch: openPlayoffMatch)
                    .padding(.top, 8)
            } else {
                clinchWindowContent
            }
        }
        .background(Color.dsBgGrouped)
        // The Playoffs chip is a SEPARATE scroll view, so it tears down the match list's
        // ScrollViewReader. Reset the one-time position flag so returning to NWSL/My teams
        // re-runs the position-to-today path (hidden → anchor → reveal), instead of resting
        // at the season opener.
        .onAppear { hasPositioned = false }
    }

    private var clinchWindowContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            let followedAbbrs = viewModel.followedAbbreviations.sorted()
            if followedAbbrs.isEmpty {
                followPrompt.frame(minHeight: 240)
            } else {
                Text("MY PATH TO THE PLAYOFFS")
                    .trackedCaps()
                    .padding(.top, 8)
                ForEach(followedAbbrs, id: \.self) { abbr in
                    if let status = playoffs.clinchStatus(of: abbr) {
                        ClinchStatusCard(abbreviation: abbr,
                                         club: clubStore.club(forAbbreviation: abbr),
                                         status: status)
                    }
                }
            }
            // The road ahead: the published playoff windows as TBD rounds.
            ForEach(viewModel.scheduleRoundSectionsForPlayoffsChip()) { section in
                VStack(alignment: .leading, spacing: 10) {
                    RoundHeader(section: section)
                    VStack(spacing: DS.cardGap) {
                        ForEach(section.matchups) { m in
                            PlayoffMatchupRow(matchup: m)
                        }
                    }
                    .padding(.leading, 16)
                    .overlay(Rectangle().fill(RoundHeader.color(for: section.status).opacity(0.3)).frame(width: 2),
                             alignment: .leading)
                }
            }
        }
        .padding(.horizontal, DS.pagePadding)
        .padding(.bottom, 20)
    }

    /// Open a playoff matchup's detail — resolve from the season first, else the simulator's
    /// source events (DEBUG runs use synthetic events that aren't in MatchStore).
    private func openPlayoffMatch(_ eventID: String) {
        if let match = matchStore.scheduledMatch(for: eventID) {
            pushedMatch = match
        } else if let event = playoffs.event(forID: eventID) {
            pushedMatch = ScheduledMatch(event: event, competition: .nwsl)
        } else {
            return
        }
        isShowingPushedMatch = true
    }

    private func matchList(_ sections: [ScheduleViewModel.ScheduleSection]) -> some View {
        // ScrollViewReader (not `.scrollPosition`) so we can anchor to a specific
        // CARD — the last kicked-off game — rather than a day-section: that card lands
        // at the very top with today's date bar + upcoming fixtures just below (so the
        // last result is the first row and history is obviously scrollable above).
        // The list is hidden until that first anchor lands, then revealed — no
        // March-then-scroll flash. Re-anchors (filter change, re-tap) animate.
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12, pinnedViews: [.sectionHeaders]) {
                    ForEach(sections) { scheduleSection in
                        switch scheduleSection {
                        case .day(let section):
                            Section {
                                ForEach(section.matches) { match in
                                    // Closure-based NavigationLink (not value-based): Event
                                    // isn't Hashable, and the card is the link's label so the
                                    // whole card is tappable. `.plain` keeps the card's look.
                                    NavigationLink {
                                        MatchDetailView(event: match.event,
                                                        competition: match.competition)
                                    } label: {
                                        MatchCard(match: match, anchor: matchStore.tickAnchor(for: match.event.id))
                                    }
                                    .buttonStyle(.plain)
                                    // The per-card scroll anchor target (event id).
                                    .id(match.id)
                                }
                            } header: {
                                DayHeader(dayKey: section.id, isToday: section.isToday)
                            }
                        case .round(let section):
                            roundSection(section)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .background(Color.dsBgGrouped)
            // Pull-to-refresh: silently refetch the season so live scores/minutes advance
            // on demand. The live-poll loop + foreground refresh (RootTabView) keep this
            // current automatically; this is the manual escape hatch. `refresh()` (not
            // `load()`) → no full-screen spinner, keeps the last good schedule on a miss.
            .refreshable { await matchStore.refresh() }
            // Hidden until the first anchor lands (no flash), then revealed positioned.
            .opacity(hasPositioned ? 1 : 0)
            .onAppear {
                guard !hasPositioned else { return }
                anchorToBoundary(proxy, animated: false)
                hasPositioned = true
            }
            // Filter change → land on that filter's own boundary (animated is fine).
            .onChange(of: selectedFilter) { _, _ in anchorToBoundary(proxy, animated: true) }
            // Re-tapping the active Schedule tab snaps back to the rest boundary.
            .onChange(of: router.reselectNonce) { _, _ in
                guard router.reselectedTab == .schedule else { return }
                anchorToBoundary(proxy, animated: true)
            }
            // (The pushed-match destination + push-tap deep-link handlers now live at the
            // NavigationStack level — see `body` — so a tap works from any chip, incl. Playoffs.)
            // "My teams" needs the club directory, which resolves a beat after the
            // season; re-anchor when those clubs land so it isn't stuck at the opener.
            .onChange(of: viewModel.clubs.isEmpty) { _, isEmpty in
                guard !isEmpty, selectedFilter == .myTeams else { return }
                anchorToBoundary(proxy, animated: false)
            }
        }
    }

    /// Consume a pending push-tap deep link once the season can resolve it.
    private func consumePendingMatch() {
        guard let id = router.pendingMatchEventID,
              let match = matchStore.scheduledMatch(for: id) else { return }
        router.pendingMatchEventID = nil
        pushedMatch = match
        isShowingPushedMatch = true
    }

    /// Scroll so the rest "boundary" card (the last kicked-off game) is at the top —
    /// the schedule's landing position. No-op when the filter has no dated games.
    private func anchorToBoundary(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let id = viewModel.initialScrollEventID(for: selectedFilter) else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .top) }
        } else {
            proxy.scrollTo(id, anchor: .top)
        }
    }

    // MARK: - Postseason round sections (the playoff merge: the bracket IS the schedule)

    /// One postseason round in the schedule list: a pinned round header (status dot + title +
    /// date range) with the round's games under the owner's status-color left bar. Rows are
    /// PlayoffMatchupRow — MatchCard's anatomy, so playoff games read like every other game.
    @ViewBuilder
    private func roundSection(_ section: ScheduleViewModel.RoundSection) -> some View {
        Section {
            // The personal "Win →" line rides at the top of the postseason region (the first
            // round section) when a followed team is still alive.
            if playoffs.bracket?.rounds.first?.slug == section.round.slug,
               let context = winContextLine {
                winContextCard(context)
            }
            VStack(spacing: DS.cardGap) {
                ForEach(section.matchups) { m in playoffRow(m) }
            }
            .padding(.leading, 16)
            .overlay(Rectangle().fill(RoundHeader.color(for: section.status).opacity(0.3)).frame(width: 2),
                     alignment: .leading)
        } header: {
            RoundHeader(section: section)
        }
    }

    @ViewBuilder
    private func playoffRow(_ m: PlayoffMatchup) -> some View {
        let row = PlayoffMatchupRow(
            matchup: m,
            homeClub: m.home.abbreviation.flatMap { clubStore.club(forAbbreviation: $0) },
            awayClub: m.away.abbreviation.flatMap { clubStore.club(forAbbreviation: $0) },
            followedAbbreviations: viewModel.followedAbbreviations
        )
        if let id = m.eventID, m.isResolved {
            Button { openPlayoffMatch(id) } label: { row }
                .buttonStyle(.plain)
                .id(id)   // scroll-anchor target, same as day cards (event id)
        } else {
            row   // TBD/projected rows aren't tappable (no event yet)
        }
    }

    /// "Win → face Portland Thorns FC in the Semifinal" for the first followed team still alive.
    private var winContextLine: String? {
        guard let bracket = playoffs.bracket else { return nil }
        let followed = viewModel.followedAbbreviations
        guard let team = bracket.seeds.keys.filter({ followed.contains($0) })
            .sorted(by: { (bracket.seeds[$0] ?? 99) < (bracket.seeds[$1] ?? 99) })
            .first(where: { bracket.isAlive($0) }),
              let step = bracket.path(forAbbreviation: team)?.first(where: { $0.winContext != nil }),
              var text = step.winContext
        else { return nil }
        // Humanize abbreviations to full club names where the directory can resolve them.
        for abbr in bracket.seeds.keys {
            if let name = clubStore.club(forAbbreviation: abbr)?.displayName {
                text = text.replacingOccurrences(of: " \(abbr) ", with: " \(name) ")
                if text.hasSuffix(" \(abbr)") { text = String(text.dropLast(abbr.count)) + name }
            }
        }
        return text
    }

    private func winContextCard(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Win →").dsFont(13, weight: .heavy).foregroundStyle(Color.dsStateKickoff)
            Text(text).dsFont(13).foregroundStyle(Color.dsFgSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.dsStateKickoff.opacity(0.08), in: RoundedRectangle(cornerRadius: DS.radiusLg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusLg, style: .continuous)
            .strokeBorder(Color.dsStateKickoff.opacity(0.2)))
    }

    // "My teams" with nothing followed yet — a gentle nudge, per the spec.
    private var followPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "star")
                .dsFont(40)
                .foregroundStyle(.secondary)
            Text("Follow your teams to see their matches here")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Tap the star on any club in the Teams tab.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    // A filter that resolves to no matches (e.g. all of a followed team's games
    // already played). Rare, but never show a blank screen.
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar")
                .dsFont(40)
                .foregroundStyle(.secondary)
            // Honest + contextual: a followed team (incl. a sparse national team) with no fixtures
            // in the season feed reads as a real "no matches" state, never a blank screen.
            Text(selectedFilter == .myTeams ? "No matches for your teams yet" : "No matches to show")
                .font(.headline)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private func errorView(_ message: String, retry: @escaping () async -> Void) -> some View {
        RetryStateView(message: message) {
            await retry()
        }
    }

}

/// Sticky day label between groups of cards (redesign): "SAT · MAR 14" with a
/// cyan TODAY chip on the current day and a trailing hairline rule. Opaque page
/// background so cards scrolling underneath don't bleed through while pinned.
private struct DayHeader: View {
    let dayKey: String     // "yyyy-MM-dd"
    let isToday: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(formatted)
                .dsFont(12, weight: .bold)
                .tracking(0.6)
                .foregroundStyle(isToday ? Color.dsFgPrimary : Color.dsFgSecondary)
            if isToday {
                Text("TODAY")
                    .dsFont(10, weight: .bold)
                    .tracking(0.5)
                    .foregroundStyle(Color.dsStateKickoff)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.dsStateKickoff.opacity(0.14), in: Capsule())
            }
            Rectangle()
                .fill(Color.dsSeparator)
                .frame(height: 1)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity)
        .background(Color.dsBgGrouped)
    }

    // "SAT · MAR 14" from the yyyy-MM-dd section key.
    private var formatted: String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = .current
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: dayKey) else { return dayKey }
        let out = DateFormatter()
        out.locale = .current
        out.timeZone = .current
        out.dateFormat = "EEE '·' MMM d"
        return out.string(from: date).uppercased()
    }
}

/// Sticky POSTSEASON round label — the DayHeader's sibling for the playoff merge: a status dot
/// (cyan upcoming / red live / green complete) + the round title in status-colored tracked caps +
/// the date range, over the same opaque page background so pinned headers don't bleed.
private struct RoundHeader: View {
    let section: ScheduleViewModel.RoundSection

    static func color(for status: ScheduleViewModel.RoundSection.Status) -> Color {
        switch status {
        case .upcoming: return .dsStateKickoff
        case .live: return .dsStateLive
        case .complete: return .dsStateFinal
        }
    }

    var body: some View {
        let color = Self.color(for: section.status)
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(section.round.title).trackedCaps(size: 12, tracking: 0.6, color: color)
            if let range = section.dateRangeLabel {
                Text("· \(range)").dsFont(12, weight: .semibold).foregroundStyle(Color.dsFgSecondary)
            } else if section.status == .complete {
                Text("· Complete").dsFont(12, weight: .semibold).foregroundStyle(Color.dsFgSecondary)
            }
            Rectangle()
                .fill(Color.dsSeparator)
                .frame(height: 1)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity)
        .background(Color.dsBgGrouped)
    }
}

/// One followed team's clinch-window status ("my path to the playoffs"): crest + club + the
/// mathematical status — ✓ Clinched (green) / In position (cyan) / Out of the picture /
/// Eliminated. Conservative math only (see PlayoffClinch) — never a false "clinched".
private struct ClinchStatusCard: View {
    let abbreviation: String
    let club: Club?
    let status: PlayoffClinch.Status

    var body: some View {
        HStack(spacing: 12) {
            TeamLogo(urlString: club?.logoURL, teamAbbreviation: abbreviation, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(club?.displayName ?? abbreviation)
                    .dsFont(15, weight: .bold)
                    .foregroundStyle(Color.dsFgPrimary)
                statusLine
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsBgCard, in: RoundedRectangle(cornerRadius: DS.radiusLg, style: .continuous))
    }

    @ViewBuilder
    private var statusLine: some View {
        switch status {
        case .clinched:
            Text("✓ Clinched a playoff spot")
                .dsFont(13, weight: .semibold).foregroundStyle(Color.dsStateFinal)
        case .inPosition(let rank, let gamesLeft):
            Text("In position — #\(rank), \(gamesLeft) game\(gamesLeft == 1 ? "" : "s") left")
                .dsFont(13, weight: .semibold).foregroundStyle(Color.dsStateKickoff)
        case .outOfPicture:
            Text("Outside the playoff line")
                .dsFont(13, weight: .semibold).foregroundStyle(Color.dsFgSecondary)
        case .eliminated:
            Text("Out of the playoff race")
                .dsFont(13, weight: .semibold).foregroundStyle(Color.dsFgTertiary)
        }
    }
}

#Preview {
    ScheduleView()
        .environment(MatchStore())
        .environment(ClubStore())
        .environment(FollowingStore())
        .environment(AppRouter())
        .environment(PlayoffStore())
}
