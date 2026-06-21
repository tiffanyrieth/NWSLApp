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
    /// The Feed's source-class filter (the chip bar): All · News · Clubs · Reporters
    /// · Players, keyed off each card's `sourceType`. (Reporters also covers NWSL
    /// media/league-outlet accounts — the `league` source class.)
    enum ContentFilter: String, CaseIterable, Hashable {
        case all, news, clubs, reporters, players

        var label: String {
            switch self {
            case .all:       return "All"
            case .news:      return "News"
            case .clubs:     return "Clubs"
            case .reporters: return "Reporters"
            case .players:   return "Players"
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

    /// Cards visible for the current `selectedFilter`. The base set is scoped to the
    /// user's world (followed teams + league-wide), narrowed by the content-type chip
    /// and the user's content preferences, then arranged in TWO LANES (no time window):
    ///  • Club lane — a followed club's OWN posts → count-based equal share per club
    ///    (`ContentRoundRobin.balanced`), so a chatty club never crowds out a quiet one
    ///    and a club that's been silent still surfaces its most-recent posts.
    ///  • League lane — reporters / league outlets / news / players (no per-club team)
    ///    → chronological, capped + woven in so it can't push club content below its
    ///    equal share.
    /// On a club-only chip the league lane is empty (→ just the balanced clubs); on a
    /// league chip (News/Reporters/Players) the club lane is empty (→ chronological).
    func items(_ following: FollowingStore, preferences: FeedPreferencesStore) -> [ContentCard] {
        let followed = Set(followedClubs(following).map(\.abbreviation))
        let filtered = allItems
            .filter { isRelevant($0, followed) }
            .filter { passesFilter($0) }
            .filter { passesPreferences($0, preferences) }
        return Self.arrange(filtered, followedAbbreviations: followedClubs(following).map(\.abbreviation))
    }

    /// PURE two-lane arrangement (no time window, count-based — unit-tested):
    ///  • Club lane — each followed club's OWN posts balanced to an EQUAL per-club share
    ///    (`ContentRoundRobin.balanced`), volume-blind and age-agnostic.
    ///  • League lane — reporters / league / news / players (no per-club team), newest-first,
    ///    capped + woven in so it can't push club content below its share.
    /// `orderedClubs` is the followed clubs in stable (directory/alphabetical) order.
    static func arrange(_ filtered: [ContentCard], followedAbbreviations orderedClubs: [String]) -> [ContentCard] {
        let followed = Set(orderedClubs)
        let balancedClubs = ContentRoundRobin.balanced(
            cards: filtered.filter { isClubScoped($0, followed) },
            followedAbbreviations: orderedClubs,
            slotsPerClub: ContentRoundRobin.feedSlotsPerClub(orderedClubs.count)
        ).cards
        let leagueLane = filtered
            .filter { !isClubScoped($0, followed) }
            .sorted { $0.timestamp > $1.timestamp }
        return merge(club: balancedClubs, league: leagueLane)
    }

    /// A card that belongs to ONE followed club (its own official posts) — the only
    /// content the per-club fairness applies to. Reporters/league/news/players are
    /// league-wide (no team) and ride the league lane.
    static func isClubScoped(_ card: ContentCard, _ followed: Set<String>) -> Bool {
        guard sourceType(of: card) == .club, let abbr = card.teamAbbreviation else { return false }
        return followed.contains(abbr)
    }

    /// Weave the league lane into the balanced club lane at a bounded ~2 club : 1 league
    /// cadence, with the league lane capped at the club count. Club content always leads
    /// each cycle, so league voices appear at natural spots but can never push a club's
    /// fair share down. Either lane empty → the other, unchanged.
    static func merge(club: [ContentCard], league: [ContentCard]) -> [ContentCard] {
        guard !club.isEmpty else { return league }
        guard !league.isEmpty else { return club }
        let cappedLeague = Array(league.prefix(min(league.count, club.count)))
        var result: [ContentCard] = []
        var ci = 0, li = 0
        while ci < club.count || li < cappedLeague.count {
            if ci < club.count { result.append(club[ci]); ci += 1 }
            if ci < club.count { result.append(club[ci]); ci += 1 }
            if li < cappedLeague.count { result.append(cappedLeague[li]); li += 1 }
        }
        return result
    }

    /// Base scope: a Feed-eligible card that's either league-wide or about a
    /// followed team. (Home-only cards never appear in the Feed.)
    private func isRelevant(_ card: ContentCard, _ followed: Set<String>) -> Bool {
        guard card.placement != .home else { return false }
        if card.isLeague { return true }
        if let abbr = card.teamAbbreviation { return followed.contains(abbr) }
        return false
    }

    /// The chip → which source classes it admits, keyed off `sourceType(of:)`.
    /// Reporters also covers `league` (NWSL media/league-outlet social accounts).
    private func passesFilter(_ card: ContentCard) -> Bool {
        switch selectedFilter {
        case .all:       return true
        case .news:      return Self.sourceType(of: card) == .news
        case .clubs:     return Self.sourceType(of: card) == .club
        case .reporters: return Self.sourceType(of: card) == .reporter || Self.sourceType(of: card) == .league
        case .players:   return Self.sourceType(of: card) == .player
        }
    }

    /// The card's source class: the proxy-set `sourceType` when present, else
    /// inferred from `layout` (seed/older cards, and player IG cards from a cron
    /// snapshot built before the proxy emitted `sourceType`). On the Feed,
    /// socialVideo/IG is a player clip (club social is placement "home").
    static func sourceType(of card: ContentCard) -> ContentCard.SourceType {
        if let t = card.sourceType { return t }
        switch card.layout {
        case .newsArticle:                          return .news
        case .blueskyReporter:                      return .reporter
        case .blueskyTeamText, .blueskyTeamMedia:   return .club
        case .youtube:                              return .club
        case .socialVideo, .instagramFallback:      return .player
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
