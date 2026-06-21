//
//  FeedView.swift
//  NWSLApp
//
//  The Feed tab — "the world talking about your teams" (reporters, news
//  outlets), filtered to the clubs you follow. Built per
//  Reference/Design/feed-tab-design-spec.md.
//
//  Layout: a title with a settings gear (source management), a pinned row of
//  filter chips below it (All · one per followed team with a color dot · League),
//  and a chronological scroll of FeedCards. Chips stay put while the content
//  scrolls (same "always-visible filter" pattern as the Schedule tab).
//
//  Home owns no Feed data beyond the shared FollowingStore it reads from the
//  environment: FeedViewModel holds the live `/feed` items and the club directory
//  it fetches to build the chips, and derives the visible list for the selected
//  chip. Content is live via `ContentService` → the proxy `/feed` route; a failed
//  fetch surfaces an honest "Couldn't load — tap to retry" (no seed fallback).
//

import SwiftUI

struct FeedView: View {
    @State private var viewModel = FeedViewModel()
    @State private var showSources = false
    // One-time coach mark pointing at the source-management gear — the feed looks like an
    // algorithmic feed you can't control, so first-time users miss it. Same pattern as the
    // Teams-tab bell coach mark (`hasSeenTeamsAlertTooltip`).
    @AppStorage("hasSeenSocialGearTooltip") private var hasSeenGearTooltip = false
    @State private var showGearTooltip = false
    @Environment(FollowingStore.self) private var following
    @Environment(FeedPreferencesStore.self) private var feedPreferences
    // The shared club directory (injected in RootTabView), for the per-team chips.
    @Environment(ClubStore.self) private var clubStore
    // The shared, prewarmable Feed store (injected in RootTabView) — the cards + load state.
    @Environment(FeedStore.self) private var feedStore

    var body: some View {
        NavigationStack {
            Group {
                if let message = errorMessage {
                    errorView(message)
                } else if !isReady {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    feed
                }
            }
            // Custom large-title header (title + gear + subtitle) like the other
            // facelifted tabs; the system nav bar is hidden so the header owns the top.
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) { feedHeader }
            .sheet(isPresented: $showSources) {
                FeedSourcesView(sources: viewModel.sources())
                    .environment(feedPreferences)
            }
        }
        .task {
            // Open to the user's default chip (Content preferences → Default view).
            viewModel.selectedFilter =
                FeedViewModel.ContentFilter(rawValue: feedPreferences.defaultFeedFilter) ?? .all
            // Hand the view model the shared directory, load the seed items, then
            // load the directory once (guarding on .idle so another tab having
            // loaded it first doesn't refetch). Items load independently of the
            // directory's state so the Feed populates even when the store was
            // already loaded elsewhere.
            viewModel.clubStore = clubStore
            viewModel.store = feedStore
            await clubStore.loadIfNeeded()   // dedupe-aware: scope the feed only after clubs are loaded
            await viewModel.loadItemsIfNeeded(following: following)
        }
        .onAppear { showGearTooltipIfNeeded() }
    }

    // Large "Feed" title + a circular gear (source management) + subtitle, drawn as
    // one pinned header (matches the Home / Schedule facelift headers).
    private var feedHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center) {
                Text("Social")
                    .dsFont(32, weight: .bold)
                    .foregroundStyle(Color.dsFgPrimary)
                Spacer()
                Button {
                    if showGearTooltip { dismissGearTooltip() }
                    showSources = true
                } label: {
                    ZStack {
                        Circle().fill(Color.dsBgCard)
                        Image(systemName: "gearshape")
                            .dsFont(16)
                            .foregroundStyle(Color.dsAccent)
                    }
                    .frame(width: 38, height: 38)
                }
                .accessibilityLabel("Manage sources")
            }
            Text("The world talking about your teams")
                .dsFont(13)
                .foregroundStyle(Color.dsFgSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsBgGrouped)
        // Coach mark hangs below the gear, arrow up. Anchored to the padded header so it
        // stays inset from the screen edge (same placement as the Teams-tab bell mark).
        .overlay(alignment: .topTrailing) {
            if showGearTooltip {
                gearTooltip
                    .fixedSize()
                    .padding(.trailing, 16)
                    .offset(y: 44)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .topTrailing)))
            }
        }
    }

    // A small blue callout under the gear (arrow up), shown once. Tapping it dismisses
    // (so does tapping the gear, or anywhere else).
    private var gearTooltip: some View {
        VStack(alignment: .trailing, spacing: 0) {
            CoachMarkTriangle()
                .fill(Color.dsAccent)
                .frame(width: 16, height: 8)
                .padding(.trailing, 12)
            Text("Customize your feed — choose which sources you see")
                .dsFont(13, weight: .semibold)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.dsAccent, in: RoundedRectangle(cornerRadius: 10))
        }
        .onTapGesture { dismissGearTooltip() }
        .accessibilityLabel("Customize your feed. Tap the gear to choose which sources you see.")
    }

    // Show once on first Social-tab visit; mark seen on show (not just dismiss) so it's
    // truly one-and-done across force-quit / returning from a sheet.
    private func showGearTooltipIfNeeded() {
        guard !hasSeenGearTooltip else { return }
        hasSeenGearTooltip = true
        withAnimation(.easeOut(duration: 0.25).delay(0.35)) {
            showGearTooltip = true
        }
    }

    private func dismissGearTooltip() {
        hasSeenGearTooltip = true
        withAnimation(.easeOut(duration: 0.2)) { showGearTooltip = false }
    }

    // MARK: - Feed (chips + content)

    private var feed: some View {
        VStack(spacing: 0) {
            chipsBar
            Divider()
            content
        }
        .background(Color.dsBgGrouped)
        // Tap anywhere in the feed dismisses the gear coach mark (runs alongside the
        // cards' own taps; no-op once it's gone).
        .simultaneousGesture(TapGesture().onEnded {
            if showGearTooltip { dismissGearTooltip() }
        })
    }

    // All 5 chips on ONE row, no horizontal scroll (Feed.html): content-sized pills
    // distributed across the width (space-between).
    private var chipsBar: some View {
        HStack(spacing: 6) {
            ForEach(Array(viewModel.chips.enumerated()), id: \.element) { index, filter in
                Chip(label: filter.label, isActive: viewModel.selectedFilter == filter,
                     compact: true, horizontalPadding: 10) {
                    viewModel.selectedFilter = filter
                }
                if index < viewModel.chips.count - 1 { Spacer(minLength: 0) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color.dsBgGrouped)
    }

    @ViewBuilder
    private var content: some View {
        let items = viewModel.items(following, preferences: feedPreferences)
        // Following exactly one team → every card is obviously about that team, so the
        // per-card team badge is redundant noise (same gate Home uses). Part B Bug 7.
        let hideTeamIdentity = viewModel.followedClubs(following).count <= 1
        if !items.isEmpty {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(items) { card in
                        ContentCardView(card: card, club: club(for: card),
                                        hideTeamIdentity: hideTeamIdentity, unified: true)
                    }
                }
                .padding(16)
            }
            .refreshable { await viewModel.load(following: following) }
        } else if viewModel.hasCompletedItemsLoad && !viewModel.isLoadingItems {
            emptyState                          // a load actually completed: genuinely no posts for this filter
        } else {
            // Still loading (incl. the directory-load → items-load gap): an honest loading state,
            // NEVER the "No posts yet" copy — a loading state must not look identical to success (#5).
            ProgressView("Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Empty / loading / error

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .dsFont(40)
                .foregroundStyle(.secondary)
            Text(emptyMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Resolve the club a card is about (for the team-colored layouts) from the
    /// shared directory; nil for reporter/league/creator cards.
    private func club(for card: ContentCard) -> Club? {
        guard let abbr = card.teamAbbreviation else { return nil }
        return clubStore.clubs.first { $0.abbreviation == abbr }
    }

    /// Contextual empty copy — names the selected content type so it reads
    /// deliberately.
    private var emptyMessage: String {
        switch viewModel.selectedFilter {
        case .all:
            return "No posts yet. As your teams make news, it'll show up here."
        case .news:
            return "No headlines right now. Check back soon."
        case .clubs:
            return "No club posts right now. Check back soon."
        case .reporters:
            return "No reporter posts right now. Check back soon."
        case .players:
            return "No player posts right now. Check back soon."
        }
    }

    private var errorMessage: String? {
        if case .error(let m) = viewModel.clubsState { return m }
        // Online-only: a failed `/feed` fetch surfaces honestly (no stale/seed fallback).
        return viewModel.itemsError
    }

    private var isReady: Bool {
        if case .loaded = viewModel.clubsState { return true }
        return false
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Button("Try again") { Task { await viewModel.load(following: following) } }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    FeedView()
        .environment(FollowingStore())
        .environment(FeedPreferencesStore())
        .environment(ClubStore())
}
