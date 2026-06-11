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
//  environment: FeedViewModel holds the (TEMP seed) items and the club directory
//  it fetches to build the chips, and derives the visible list for the selected
//  chip. Today's content is a curated static seed (see FeedContentProvider) so
//  the tab is real and testable before a content backend exists.
//

import SwiftUI

struct FeedView: View {
    @State private var viewModel = FeedViewModel()
    @State private var showSources = false
    @Environment(FollowingStore.self) private var following
    @Environment(FeedPreferencesStore.self) private var feedPreferences
    // The shared club directory (injected in RootTabView), for the per-team chips.
    @Environment(ClubStore.self) private var clubStore

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
            .navigationTitle("Feed")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSources = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Manage sources")
                }
            }
            .sheet(isPresented: $showSources) {
                FeedSourcesView(sources: viewModel.sources())
                    .environment(feedPreferences)
            }
        }
        .task {
            // Hand the view model the shared directory, load the seed items, then
            // load the directory once (guarding on .idle so another tab having
            // loaded it first doesn't refetch). Items load independently of the
            // directory's state so the Feed populates even when the store was
            // already loaded elsewhere.
            viewModel.clubStore = clubStore
            if case .idle = clubStore.state { await clubStore.load() }
            await viewModel.loadItemsIfNeeded(following: following)
        }
    }

    // MARK: - Feed (chips + content)

    private var feed: some View {
        VStack(spacing: 0) {
            chipsBar
            Divider()
            content
        }
        .background(Color.dsBgGrouped)
    }

    private var chipsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.chips, id: \.self) { filter in
                    Chip(label: filter.label, isActive: viewModel.selectedFilter == filter) {
                        viewModel.selectedFilter = filter
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color.dsBgGrouped)
    }

    @ViewBuilder
    private var content: some View {
        let items = viewModel.items(following, preferences: feedPreferences)
        if items.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(items) { card in
                        ContentCardView(card: card, club: club(for: card))
                    }
                }
                .padding(16)
            }
            .refreshable { await viewModel.load(following: following) }
        }
    }

    // MARK: - Empty / loading / error

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 40))
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
        case .reporters:
            return "No reporter posts right now. Check back soon."
        case .news:
            return "No news articles right now. Check back soon."
        case .social:
            return "No social clips right now. Check back soon."
        }
    }

    private var errorMessage: String? {
        if case .error(let m) = viewModel.clubsState { return m }
        return nil
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
