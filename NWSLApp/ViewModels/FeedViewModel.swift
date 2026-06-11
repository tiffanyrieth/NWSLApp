//
//  FeedViewModel.swift
//  NWSLApp
//
//  Owns the Feed tab's state. Two inputs come together here:
//   • the feed cards (today a TEMP curated seed from FeedContentProvider; later a
//     real Bluesky/Reddit/news backend), and
//   • the user's followed clubs (from the shared ClubStore), which scope the base
//     set — the Feed only ever shows content about teams the user follows plus
//     league-wide items.
//
//  The filter chips are CONTENT-TYPE, not per-team (All / Reporters / News /
//  Social). The Feed is the league-wide "soccer conversation" — content is already
//  scoped by the user's follows, so team chips would over-filter; team-specific
//  content lives on Home. The chip then narrows by card layout.
//
//  Filtering, in order:
//   1. Base — placement != .home, AND (about a followed team OR league-wide).
//   2. Chip — All / Reporters (blueskyReporter) / News (newsArticle) /
//      Social (socialVideo + instagramFallback).
//   3. Preferences — drop muted sources + toggled-off content types.
//   4. Staleness (≤7 days) + reverse-chronological.
//

import Foundation

@Observable
final class FeedViewModel {
    /// The Feed's content-type filter (the chip bar). Replaces the old per-team
    /// chips — see the file note.
    enum ContentFilter: String, CaseIterable, Hashable {
        case all, reporters, news, social

        var label: String {
            switch self {
            case .all:       return "All"
            case .reporters: return "Reporters"
            case .news:      return "News"
            case .social:    return "Social"
            }
        }
    }

    /// A distinct source powering the Feed, for the Sources sheet's mute list.
    /// `name` matches `ContentCard.muteKey` (the mute key); `detail` is the handle
    /// for reporters or a content-type label for outlets/creators.
    struct Source: Identifiable, Hashable {
        let name: String
        let detail: String
        var id: String { name }
    }

    // The shared club directory, handed in by the view (mirrors Home/Schedule):
    // used to scope the base set to followed teams. Until it's wired, `.idle`.
    var clubStore: ClubStore?

    private(set) var allItems: [ContentCard] = []
    var selectedFilter: ContentFilter = .all

    private let content: FeedContentProvider

    init(content: FeedContentProvider = FeedContentProvider()) {
        self.content = content
    }

    /// Proxies the shared club store's state so the view's error/ready checks over
    /// idle/loading/loaded/error are unchanged.
    var clubsState: ClubStore.State { clubStore?.state ?? .idle }

    /// Load the seed cards, then (re)load the shared directory. Used by
    /// pull-to-refresh; first appearance loads cards + directory separately.
    func load() async {
        allItems = (await content.items()).sorted { $0.timestamp > $1.timestamp }
        await clubStore?.load()
    }

    /// Loads the (TEMP seed) cards if not already loaded — kept SEPARATE from the
    /// directory load so the Feed still populates when the shared ClubStore was
    /// already loaded by another tab (Home, the landing tab, usually loads it first).
    func loadItemsIfNeeded() async {
        guard allItems.isEmpty else { return }
        allItems = (await content.items()).sorted { $0.timestamp > $1.timestamp }
    }

    private var clubs: [Club] { clubStore?.clubs ?? [] }

    /// Followed clubs, in the directory's alphabetical order.
    func followedClubs(_ following: FollowingStore) -> [Club] {
        clubs.filter { following.followedIDs.contains($0.id) }
    }

    // MARK: - Chips

    /// The four content-type chips, fixed (no per-team chips — see the file note).
    var chips: [ContentFilter] { ContentFilter.allCases }

    // MARK: - Filtered cards

    /// Cards visible for the current `selectedFilter`, already newest-first. The
    /// base set is always scoped to the user's world (followed teams + league-wide),
    /// then narrowed by the content-type chip and the user's content preferences.
    func items(_ following: FollowingStore, preferences: FeedPreferencesStore) -> [ContentCard] {
        let followed = Set(followedClubs(following).map(\.abbreviation))
        return allItems
            .filter { isRelevant($0, followed) }
            .filter { passesFilter($0) }
            .filter { passesPreferences($0, preferences) }
            .fresh(.feed)
            .sorted { $0.timestamp > $1.timestamp }
    }

    /// Base scope: a Feed-eligible card that's either league-wide or about a
    /// followed team. (Home-only cards never appear in the Feed.)
    private func isRelevant(_ card: ContentCard, _ followed: Set<String>) -> Bool {
        guard card.placement != .home else { return false }
        if card.isLeague { return true }
        if let abbr = card.teamAbbreviation { return followed.contains(abbr) }
        return false
    }

    /// The content-type chip → which layouts it admits.
    private func passesFilter(_ card: ContentCard) -> Bool {
        switch selectedFilter {
        case .all:       return true
        case .reporters: return card.layout == .blueskyReporter
        case .news:      return card.layout == .newsArticle
        case .social:    return card.layout == .socialVideo || card.layout == .instagramFallback
        }
    }

    /// Honor the content preferences: drop muted sources and toggled-off types.
    /// (Only the reporter/article toggles exist; other layouts always pass.)
    private func passesPreferences(_ card: ContentCard, _ prefs: FeedPreferencesStore) -> Bool {
        if prefs.isMuted(card.muteKey) { return false }
        switch card.layout {
        case .blueskyReporter: return prefs.showReporterPosts
        case .newsArticle:     return prefs.showArticleLinks
        default:               return true
        }
    }

    /// The distinct sources powering the Feed, alphabetical — for the mute list.
    func sources() -> [Source] {
        var seen = Set<String>()
        var result: [Source] = []
        for item in allItems {
            let key = item.muteKey
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            let detail = item.handle ?? item.sourceName ?? item.platform.rawValue.capitalized
            result.append(Source(name: key, detail: detail))
        }
        return result.sorted { $0.name < $1.name }
    }
}
