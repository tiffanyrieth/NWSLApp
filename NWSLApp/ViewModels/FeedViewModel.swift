//
//  FeedViewModel.swift
//  NWSLApp
//
//  Owns the Feed tab's state. Two inputs come together here:
//   • the feed cards (LIVE as of A2 — real Bluesky reporter/league/team posts via
//     `ContentService.feedCards` → the proxy `/feed` route; the curated seed is the
//     offline-first fallback. Reddit + news RSS extend the same route later), and
//   • the user's followed clubs (from the shared ClubStore), which scope the base
//     set — the Feed only ever shows content about teams the user follows plus
//     league-wide items.
//
//  The filter chips are SOURCE-CLASS, not per-team (All / News / Clubs / Reporters /
//  Players), keyed off each card's proxy-set `sourceType`. The Feed is the
//  league-wide "soccer conversation" — content is already scoped by the user's
//  follows, so team chips would over-filter; team-specific content lives on Home.
//
//  Filtering, in order:
//   1. Base — placement != .home, AND (about a followed team OR league-wide).
//   2. Chip — All / News / Clubs / Reporters (also NWSL media + league outlets) /
//      Players, via sourceType(of:) (falls back to inferring from layout when the
//      proxy hasn't set sourceType — seed cards, or player cards from an older cron).
//   3. Preferences — drop muted sources + toggled-off content types.
//   4. Staleness (≤7 days) + reverse-chronological.
//

import Foundation

@Observable
final class FeedViewModel {
    /// The Social tab's source-class filter (the chip bar): All · Headlines · Reporters
    /// · Players · Clubs, keyed off each card's `resolvedSourceType`. Headlines covers
    /// BOTH `news` (Google-News articles) AND `league` (NWSL media/league-outlet
    /// accounts) — the league's own coverage, one chip. Declaration order IS the chip
    /// order (`chips` = `allCases`). The `.news` rawValue is kept (just relabeled) so
    /// the persisted `defaultFeedFilter` doesn't orphan.
    enum ContentFilter: String, CaseIterable, Hashable {
        case all, news, reporters, players, clubs

        var label: String {
            switch self {
            case .all:       return "All"
            case .news:      return "Headlines"
            case .reporters: return "Reporters"
            case .players:   return "Players"
            case .clubs:     return "Clubs"
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

    // The shared club directory + the shared Feed store, handed in by the view (mirrors
    // Home/Schedule). The directory scopes the display filter to followed teams; the store owns
    // the cards + load state (prewarmed in RootTabView). Until wired, the view falls back safely.
    var clubStore: ClubStore?
    var store: FeedStore?

    var selectedFilter: ContentFilter = .all

    // Feed data + load state live on the shared FeedStore now (so it can be prewarmed); the view
    // reads them through these passthroughs, so its call sites are unchanged.
    var allItems: [ContentCard] { store?.allItems ?? [] }
    var itemsError: String? { store?.itemsError }
    var isLoadingItems: Bool { store?.isLoadingItems ?? false }
    var hasCompletedItemsLoad: Bool { store?.hasCompletedItemsLoad ?? false }

    /// Proxies the shared club store's state so the view's error/ready checks over
    /// idle/loading/loaded/error are unchanged.
    var clubsState: ClubStore.State { clubStore?.state ?? .idle }

    /// (Re)load the shared directory, then the Feed cards. Used by pull-to-refresh + retry.
    func load(following: FollowingStore) async {
        guard let clubStore else { return }
        await clubStore.load()
        await store?.load(following: following, clubStore: clubStore)
    }

    /// Load the Feed cards if not already loaded (the prewarm usually beat us to it). The view
    /// loads the shared ClubStore first, so the store's scoping resolves.
    func loadItemsIfNeeded(following: FollowingStore) async {
        guard let clubStore else { return }
        await store?.loadIfNeeded(following: following, clubStore: clubStore)
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

    /// Cards visible for the current `selectedFilter`, arranged by the SAME single
    /// per-club balance as Home (no two-lane, no time window). The base set is scoped to
    /// the user's world (followed teams + league-wide), narrowed by the chip + content
    /// preferences, then every team-tagged card (club/news/reporter/player/league — the
    /// proxy team-tags ~all of them) is balanced per `teamAbbreviation` so each followed
    /// club gets an equal slot count, volume-blind. The rare genuinely team-less card is
    /// appended (never capped or laned).
    func items(_ following: FollowingStore, preferences: FeedPreferencesStore) -> [ContentCard] {
        let followed = Set(followedClubs(following).map(\.abbreviation))
        let filtered = allItems
            .filter { isRelevant($0, followed) }
            .filter { passesFilter($0) }
            .filter { passesPreferences($0, preferences) }

        return Self.arranged(filtered, followedAbbreviations: followedClubs(following).map(\.abbreviation))
    }

    /// PURE arrangement (unit-tested): single per-club balance over the team-tagged cards
    /// — identical to Home, volume-blind, age-agnostic — with the rare genuinely team-less
    /// card appended newest-first (never given a lane or a cap). `orderedClubs` is the
    /// followed clubs in stable (directory/alphabetical) order.
    static func arranged(_ filtered: [ContentCard], followedAbbreviations orderedClubs: [String]) -> [ContentCard] {
        let balanced = ContentRoundRobin.balanced(
            cards: filtered.filter { $0.teamAbbreviation != nil },
            followedAbbreviations: orderedClubs,
            slotsPerClub: ContentRoundRobin.feedSlotsPerClub(orderedClubs.count)
        ).cards
        let leagueWide = filtered
            .filter { $0.teamAbbreviation == nil }
            .sorted { $0.timestamp > $1.timestamp }
        return balanced + leagueWide
    }

    /// Base scope: a Feed-eligible card that's either league-wide or about a
    /// followed team. (Home-only cards never appear in the Feed.)
    private func isRelevant(_ card: ContentCard, _ followed: Set<String>) -> Bool {
        guard card.placement != .home else { return false }
        if card.isLeague { return true }
        if let abbr = card.teamAbbreviation { return followed.contains(abbr) }
        return false
    }

    /// The chip → which source classes it admits, keyed off `resolvedSourceType`.
    /// Headlines covers BOTH `news` (articles) AND `league` (NWSL media/league outlets);
    /// Reporters is beat writers only.
    private func passesFilter(_ card: ContentCard) -> Bool {
        switch selectedFilter {
        case .all:       return true
        case .news:      return card.resolvedSourceType == .news || card.resolvedSourceType == .league
        case .reporters: return card.resolvedSourceType == .reporter
        case .players:   return card.resolvedSourceType == .player
        case .clubs:     return card.resolvedSourceType == .club
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
