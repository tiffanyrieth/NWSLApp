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
            if case .idle = matchStore.state { await matchStore.load() }
            if case .idle = clubStore.state { await clubStore.load() }
        }
        // First-open positioning + all re-anchors live INSIDE the ScrollViewReader
        // (matchList) so they can drive the scroll proxy directly. See `matchList`.
    }

    // International is wired but has no data yet (no competition field on Event) —
    // a deliberate, designed "coming soon" state rather than a blank "No matches".
    private var internationalComingSoon: some View {
        VStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.system(size: 40))
                .foregroundStyle(Color.dsStateKickoff)
            Text("International fixtures coming soon")
                .font(.headline)
                .foregroundStyle(Color.dsFgPrimary)
                .multilineTextAlignment(.center)
            Text("National-team windows and continental cups will appear here once the schedule goes competition-aware.")
                .font(.subheadline)
                .foregroundStyle(Color.dsFgSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.dsBgGrouped)
    }

    // Large "Schedule" title + the filter chips, drawn as one pinned header.
    private var scheduleHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Schedule")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(Color.dsFgPrimary)
                .padding(.horizontal, 16)
                .padding(.top, 4)
            filterPicker
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsBgGrouped)
    }

    // Three filter chips (design: NWSL · My teams · All matches), active = accent.
    private var filterPicker: some View {
        HStack(spacing: 8) {
            ForEach(ScheduleViewModel.Filter.allCases) { filter in
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
    // states (no follows yet, or follows still resolving).
    @ViewBuilder
    private var loadedContent: some View {
        if selectedFilter == .myTeams && following.followedIDs.isEmpty {
            followPrompt
        } else if selectedFilter == .myTeams && viewModel.isResolvingFollowedTeams {
            ProgressView("Loading your teams…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if selectedFilter == .myTeams, let clubsError = viewModel.clubsError {
            // The club directory (needed to resolve My-teams) failed to load.
            // Show a real error + retry instead of a misleading "No matches" (#16).
            errorView(clubsError) { await clubStore.load() }
        } else {
            let sections = viewModel.sections(for: selectedFilter)
            if sections.isEmpty {
                if selectedFilter == .international {
                    internationalComingSoon
                } else {
                    emptyState
                }
            } else {
                matchList(sections)
            }
        }
    }

    private func matchList(_ sections: [ScheduleViewModel.DaySection]) -> some View {
        // ScrollViewReader (not `.scrollPosition`) so we can anchor to a specific
        // CARD — the last kicked-off game — rather than a day-section: that card lands
        // at the very top with today's date bar + upcoming fixtures just below (so the
        // last result is the first row and history is obviously scrollable above).
        // The list is hidden until that first anchor lands, then revealed — no
        // March-then-scroll flash. Re-anchors (filter change, re-tap) animate.
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12, pinnedViews: [.sectionHeaders]) {
                    ForEach(sections) { section in
                        Section {
                            ForEach(section.events) { event in
                                // Closure-based NavigationLink (not value-based): Event
                                // isn't Hashable, and the card is the link's label so the
                                // whole card is tappable. `.plain` keeps the card's look.
                                NavigationLink {
                                    // Pass our name so the detail's back button reads
                                    // "‹ Schedule" (parent-reflecting back rule).
                                    MatchDetailView(event: event, origin: "Schedule")
                                } label: {
                                    MatchCard(event: event)
                                }
                                .buttonStyle(.plain)
                                // The per-card scroll anchor target (event id).
                                .id(event.id)
                            }
                        } header: {
                            DayHeader(dayKey: section.id, isToday: section.isToday)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .background(Color.dsBgGrouped)
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
            // "My teams" needs the club directory, which resolves a beat after the
            // season; re-anchor when those clubs land so it isn't stuck at the opener.
            .onChange(of: viewModel.clubs.isEmpty) { _, isEmpty in
                guard !isEmpty, selectedFilter == .myTeams else { return }
                anchorToBoundary(proxy, animated: false)
            }
        }
        // No pull-to-refresh: the season loads once a year and live scores already
        // update in-card in real time, so a manual refresh has nothing to fetch.
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

    // "My teams" with nothing followed yet — a gentle nudge, per the spec.
    private var followPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "star")
                .font(.system(size: 40))
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
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No matches to show")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private func errorView(_ message: String, retry: @escaping () async -> Void) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Button("Try again") {
                Task { await retry() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                .font(.system(size: 12, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(isToday ? Color.dsFgPrimary : Color.dsFgSecondary)
            if isToday {
                Text("TODAY")
                    .font(.system(size: 10, weight: .bold))
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

#Preview {
    ScheduleView()
        .environment(MatchStore())
        .environment(ClubStore())
        .environment(FollowingStore())
        .environment(AppRouter())
}
