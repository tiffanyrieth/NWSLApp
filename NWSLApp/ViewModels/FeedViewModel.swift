//
//  FeedViewModel.swift
//  NWSLApp
//
//  Owns the Feed tab's state. Two inputs come together here:
//   • the feed items (today a TEMP curated seed from FeedContentProvider; later
//     a real Bluesky/news backend), and
//   • the user's followed clubs — resolved by fetching the club directory, the
//     same pattern Home/Schedule use, because FollowingStore stores IDs only and
//     the filter chips need each club's short name + color.
//
//  The club directory comes from the shared ClubStore (injected app-wide — one
//  fetch, many readers; see CLAUDE.md What's-Next #15), the same directory
//  Teams/Home/Schedule read; the view hands it in. The feed items themselves are
//  owned here (the TEMP seed), loaded independently of the directory.
//
//  Everything the view shows is DERIVED here: the filter chips (All + one per
//  followed team + League) and the items visible for the selected chip. The view
//  passes in the shared FollowingStore (mirroring HomeViewModel) rather than the
//  store being owned here, since following is app-wide state.
//
//  Filtering rules (per the design spec):
//   • All    — everything from followed teams + league-wide news, newest first.
//   • <team> — only items tagged to that team (incl. multi-team items).
//   • League — only league-wide news (power rankings, expansion, rule changes).
//

import Foundation

@Observable
final class FeedViewModel {
    /// Which chip is selected. `.team` carries the club abbreviation, the same
    /// key FeedTeamTag uses, so chip ↔ item matching is a simple string compare.
    enum Filter: Hashable {
        case all
        case team(String)   // club abbreviation
        case league
    }

    /// A filter chip to render: its filter and label (clean text, no dot — the
    /// chip label and the cards' own team dots already identify the team).
    struct Chip: Identifiable, Hashable {
        let filter: Filter
        let label: String
        var id: Filter { filter }
    }

    /// A distinct source powering the Feed, for the Sources sheet's mute list.
    /// `name` matches FeedItem.sourceName (the mute key); `detail` is the handle
    /// for reporters or the platform for outlets.
    struct Source: Identifiable, Hashable {
        let name: String
        let detail: String
        var id: String { name }
    }

    // The shared club directory, handed in by the view (mirrors Home/Schedule):
    // used to build the per-team chips. Until it's wired, the screen reads `.idle`.
    var clubStore: ClubStore?

    private(set) var allItems: [FeedItem] = []
    var selectedFilter: Filter = .all

    private let content: FeedContentProvider

    init(content: FeedContentProvider = FeedContentProvider()) {
        self.content = content
    }

    /// Proxies the shared club store's state so the view's error/ready checks over
    /// idle/loading/loaded/error are unchanged.
    var clubsState: ClubStore.State { clubStore?.state ?? .idle }

    /// Load the seed items, then (re)load the shared directory. Used by
    /// pull-to-refresh; the first appearance loads items + directory separately
    /// (see `loadItemsIfNeeded` and the view's `.task`).
    func load() async {
        allItems = (await content.items())
            .sorted { $0.timestamp > $1.timestamp }   // newest first
        await clubStore?.load()
    }

    /// Loads the (TEMP seed) items if not already loaded — kept SEPARATE from the
    /// directory load so the Feed still populates when the shared ClubStore was
    /// already loaded by another tab (Home, the landing tab, usually loads it
    /// first; if item-loading were gated on the directory's `.idle` it would be
    /// skipped and the Feed would show empty).
    func loadItemsIfNeeded() async {
        guard allItems.isEmpty else { return }
        allItems = (await content.items())
            .sorted { $0.timestamp > $1.timestamp }   // newest first
    }

    private var clubs: [Club] { clubStore?.clubs ?? [] }

    /// Followed clubs, in the directory's alphabetical order.
    func followedClubs(_ following: FollowingStore) -> [Club] {
        clubs.filter { following.followedIDs.contains($0.id) }
    }

    // MARK: - Chips

    /// All + one chip per followed team + League.
    func chips(_ following: FollowingStore) -> [Chip] {
        var chips: [Chip] = [Chip(filter: .all, label: "All")]
        for club in followedClubs(following) {
            chips.append(Chip(
                filter: .team(club.abbreviation),
                label: club.shortName ?? club.displayName
            ))
        }
        chips.append(Chip(filter: .league, label: "League"))
        return chips
    }

    // MARK: - Filtered items

    /// Items visible for the current `selectedFilter`, already newest-first.
    /// The base set is always scoped to the user's world — their followed teams
    /// plus league-wide news — so the Feed never shows content about clubs they
    /// don't follow. The user's content preferences (muted sources, post/article
    /// toggles) are then applied on top.
    func items(_ following: FollowingStore, preferences: FeedPreferencesStore) -> [FeedItem] {
        let followed = Set(followedClubs(following).map(\.abbreviation))
        let base: [FeedItem]
        switch selectedFilter {
        case .all:
            base = allItems.filter { $0.isLeague || isFollowed($0, followed) }
        case .league:
            base = allItems.filter { $0.isLeague }
        case .team(let abbreviation):
            base = allItems.filter { item in
                item.teams.contains { $0.abbreviation == abbreviation }
            }
        }
        return base.filter { passesPreferences($0, preferences) }
    }

    /// True if any of the item's tagged teams is one the user follows.
    private func isFollowed(_ item: FeedItem, _ followed: Set<String>) -> Bool {
        item.teams.contains { followed.contains($0.abbreviation) }
    }

    /// Honor the content preferences: drop muted sources and toggled-off kinds.
    private func passesPreferences(_ item: FeedItem, _ prefs: FeedPreferencesStore) -> Bool {
        if prefs.isMuted(item.sourceName) { return false }
        switch item.kind {
        case .reporterPost: return prefs.showReporterPosts
        case .articleLink:  return prefs.showArticleLinks
        }
    }

    /// The distinct sources powering the Feed, alphabetical — for the mute list.
    func sources() -> [Source] {
        var seen = Set<String>()
        var result: [Source] = []
        for item in allItems where !seen.contains(item.sourceName) {
            seen.insert(item.sourceName)
            result.append(Source(name: item.sourceName, detail: item.sourceHandle ?? item.platform))
        }
        return result.sorted { $0.name < $1.name }
    }
}
