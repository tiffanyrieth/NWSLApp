//
//  ScheduleView.swift
//  NWSLApp
//
//  Full-season NWSL schedule as a vertical scroll of game cards (MLS-app
//  style), grouped under sticky local-day headers. On first successful load it
//  scrolls to today's section (or the next upcoming matchday if today has no
//  matches) so fans land on what's relevant instead of the season opener.
//
//  Layout note: this is a ScrollView + LazyVStack rather than a List. That
//  gives full control over card spacing (the crisp ~4-per-screen feel) and —
//  crucially — unlocks iOS 17's `.scrollPosition(id:)`, which is reliable for
//  lazy stacks but not for List. The old List + ScrollViewReader approach
//  couldn't land the scroll-to-today reliably; this can.
//
//  Design rules honored:
//   #1 — no persistent overlays obscuring content (status lives inside each
//        card; nav title is the standard NavigationStack title bar; content
//        respects safe-area insets).
//   #2 — NavigationStack is in place so future detail pushes are reversible.
//

import SwiftUI

struct ScheduleView: View {
    @State private var viewModel = ScheduleViewModel()
    // The season's events live in the shared store (injected in RootTabView);
    // this screen reads its slice through the view model.
    @Environment(MatchStore.self) private var matchStore
    // The section the scroll view is anchored to. Set once on first load to
    // scroll to today; afterwards `.scrollPosition` owns this binding as the
    // user scrolls, and we never write it again.
    @State private var scrollTarget: String?
    // Prevents pull-to-refresh (which re-emits .loaded) from yanking the scroll
    // position back to today.
    @State private var hasScrolledToToday = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Schedule")
                .refreshable { await viewModel.load() }
        }
        // Hand the view model the shared store, then load once on first
        // appearance — guarding on `.idle` so re-selecting the tab (or another
        // screen having loaded the store first) doesn't refetch.
        .task {
            viewModel.store = matchStore
            if case .idle = matchStore.state { await viewModel.load() }
        }
        // Drive the one-time scroll-to-today off the idle/loading -> loaded
        // edge, after the LazyVStack has had a chance to realize its sections.
        .onChange(of: viewModel.isLoaded) { _, loaded in
            guard loaded, !hasScrolledToToday,
                  let target = viewModel.initialScrollSectionID else { return }
            hasScrolledToToday = true
            // One runloop hop so the sections exist before we anchor to one;
            // otherwise the position binding has no matching id to land on.
            Task { @MainActor in
                await Task.yield()
                scrollTarget = target
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("Loading schedule…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let message):
            errorView(message)
        case .loaded:
            loadedList
        }
    }

    private var loadedList: some View {
        ScrollView {
            LazyVStack(spacing: 12, pinnedViews: [.sectionHeaders]) {
                ForEach(viewModel.sections) { section in
                    Section {
                        ForEach(section.events) { event in
                            MatchCard(event: event)
                        }
                    } header: {
                        DayHeader(label: section.label)
                            .id(section.id)   // scroll-to-today anchor
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .scrollPosition(id: $scrollTarget, anchor: .top)
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .background(Color(.systemGroupedBackground))
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Button("Try again") {
                Task { await viewModel.load() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
}
