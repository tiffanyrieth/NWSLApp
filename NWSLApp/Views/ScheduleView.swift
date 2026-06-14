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
//  Layout note: this is a ScrollView + LazyVStack rather than a List. That
//  gives full control over card spacing (the crisp feel) and — crucially —
//  unlocks iOS 17's `.scrollPosition(id:)`, which is reliable for lazy stacks
//  but not for List.
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

    // Which filter tab is selected. Defaults to NWSL (the full league) so fans
    // can discover other games — NOT "My teams" (see the spec).
    @State private var selectedFilter: ScheduleViewModel.Filter = .nwsl

    // The section the scroll view is anchored to. Set on first load (scroll to
    // today) and re-set on filter change; otherwise `.scrollPosition` owns it as
    // the user scrolls.
    @State private var scrollTarget: String?
    // Prevents pull-to-refresh (which re-emits .loaded) from yanking the scroll
    // position back to today on the FIRST-load path. (Filter changes re-anchor
    // independently of this guard.)
    @State private var hasScrolledToToday = false

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
        // First-load scroll-to-today, off the idle/loading -> loaded edge.
        .onChange(of: viewModel.isLoaded) { _, loaded in
            if loaded { anchorIfNeeded() }
        }
        // The "My teams" filter also needs the club directory (it resolves a
        // beat after the season). When it lands, retry the first-load anchor —
        // otherwise My teams would open stuck at the season opener.
        .onChange(of: viewModel.clubs.isEmpty) { _, isEmpty in
            if !isEmpty { anchorIfNeeded() }
        }
        // Re-anchor when the filter changes, so each tab lands on its own next
        // upcoming match rather than keeping a now-invalid section id.
        .onChange(of: selectedFilter) { _, _ in
            anchor(to: viewModel.initialScrollSectionID(for: selectedFilter))
        }
    }

    // Large "Schedule" title + the filter chips, drawn as one pinned header.
    private var scheduleHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Schedule")
                .font(.system(size: 34, weight: .bold))
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
                Chip(label: filter.title, isActive: selectedFilter == filter) {
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
                emptyState
            } else {
                matchList(sections)
            }
        }
    }

    private func matchList(_ sections: [ScheduleViewModel.DaySection]) -> some View {
        ScrollView {
            LazyVStack(spacing: 12, pinnedViews: [.sectionHeaders]) {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.events) { event in
                            // Closure-based NavigationLink (not value-based): Event
                            // isn't Hashable, and the card is the link's label so the
                            // whole card is tappable. `.plain` keeps the card's look.
                            NavigationLink {
                                MatchDetailView(event: event)
                            } label: {
                                MatchCard(event: event)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        DayHeader(label: section.label)
                            .id(section.id)   // scroll-to anchor
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .scrollPosition(id: $scrollTarget, anchor: .top)
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .background(Color.dsBgGrouped)
        // No pull-to-refresh: the season loads once a year and live scores already
        // update in-card in real time, so a manual refresh has nothing to fetch.
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

    // First-load anchor: runs once, and only when the current filter actually
    // has a target to land on. NWSL is ready at season-load; "My teams" also
    // needs the club directory, so this may no-op on the first call and succeed
    // when clubs resolve. The guard is set only on a successful anchor, so a
    // premature call doesn't burn the one-shot.
    private func anchorIfNeeded() {
        guard !hasScrolledToToday,
              let target = viewModel.initialScrollSectionID(for: selectedFilter) else { return }
        hasScrolledToToday = true
        anchor(to: target)
    }

    // Set the scroll position to a section. One runloop hop so the LazyVStack
    // has realized the (possibly just-changed) sections before we set the binding.
    private func anchor(to target: String?) {
        guard let target else { return }
        Task { @MainActor in
            await Task.yield()
            scrollTarget = target
        }
    }
}

/// Sticky day label between groups of cards. Uses an opaque `.bar` background
/// so cards scrolling underneath don't bleed through while it's pinned.
private struct DayHeader: View {
    let label: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
}

#Preview {
    ScheduleView()
        .environment(MatchStore())
        .environment(ClubStore())
        .environment(FollowingStore())
}
