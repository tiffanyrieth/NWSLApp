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
//  The filter chips are SOURCE-CLASS, not per-team (All / Reporters / Players / Clubs),
//  keyed off each card's proxy-set `sourceType`. The Feed is YOUR clubs' "soccer
//  conversation" — content is already scoped by the user's follows; team-specific
//  framing lives on Home.
//
//  Filtering, in order:
//   1. Base — placement != .home, AND (about a followed team OR league-wide).
//   2. Recency — reporter/league/news cards older than 30 days are dropped; the user's
//      own club/player content is age-agnostic (see `isFresh`).
//   3. Chip — All / Reporters (Bluesky beat writers + outlet articles) / Players / Clubs,
//      via `resolvedSourceType`; league posts have no chip and ride All only.
//   4. Preferences — drop muted sources + toggled-off content types.
//   5. Single per-club balance (see `arranged`), reverse-chronological.
//

import Foundation

@Observable
final class FeedViewModel {
    /// The Social tab's source-class filter (the chip bar): All · Reporters · Players,
    /// keyed off each card's `resolvedSourceType`. Reporters covers BOTH `reporter`
    /// (Bluesky beat writers) AND `news` (curated-outlet RSS articles) — the same
    /// journalist voice in two formats (social post vs article), told apart by the card's
    /// REPORTER / NEWS pill. `league` (NWSL media/outlet Bluesky accounts) has NO chip — it
    /// surfaces only under All. The old CLUBS chip was retired 2026-08 (club Bluesky is
    /// sparse, low-value gameday noise, and the official club voice lives on Home Club News);
    /// club cards are dropped from Social entirely (see `isRelevant`). Declaration order IS
    /// the chip order (`chips` = `allCases`); a persisted `defaultFeedFilter` of a retired
    /// value ("news"/"clubs") falls back to All.
    enum ContentFilter: String, CaseIterable, Hashable {
        case all, reporters, players

        var label: String {
            switch self {
            case .all:       return "All"
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
        /// A reporter the USER added (Phase 3) — gets the "ADDED" badge in the Sources list.
        var isAdded: Bool = false
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

    /// Which followed club leads the per-club balance. The clubs used to arrive in the directory's
    /// fixed alphabetical order, so the same club led the Social feed on every launch and every
    /// refresh — the equal-slot guarantee held, but the club you saw FIRST never changed. Same
    /// thumb-on-the-scale the Home Club News module had.
    ///
    /// Seeded randomly per launch, advanced on each refresh. STATE rather than a `random()` inside
    /// `items(_:preferences:)`, which the view calls while rendering — re-rolling per render would
    /// reshuffle the feed under the user's thumb mid-scroll.
    private(set) var clubRotation: Int = Int.random(in: 0..<1_000)

    /// (Re)load the shared directory, then the Feed cards. Used by pull-to-refresh + retry.
    func load(following: FollowingStore, preferences: FeedPreferencesStore) async {
        guard let clubStore else { return }
        clubRotation += 1   // a different followed club leads this time (see `clubRotation`)
        await clubStore.load()
        await store?.load(following: following, clubStore: clubStore, preferences: preferences)
    }

    /// Load the Feed cards if not already loaded (the prewarm usually beat us to it). The view
    /// loads the shared ClubStore first, so the store's scoping resolves.
    func loadItemsIfNeeded(following: FollowingStore, preferences: FeedPreferencesStore) async {
        guard let clubStore else { return }
        await store?.loadIfNeeded(following: following, clubStore: clubStore, preferences: preferences)
    }

    private var clubs: [Club] { clubStore?.clubs ?? [] }

    /// Followed clubs, in the directory's alphabetical order.
    func followedClubs(_ following: FollowingStore) -> [Club] {
        clubs.filter { following.followedIDs.contains($0.id) }
    }

    // MARK: - Chips

    /// The three content-type chips, fixed (no per-team chips — see the file note).
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
        let now = Date()
        let filtered = allItems
            .filter { isRelevant($0, followed) }
            .filter { Self.isFresh($0, now: now) }
            .filter { passesFilter($0) }
            .filter { passesPreferences($0, preferences) }
            .filter { passesPlayerFollow($0, followed, preferences) }

        // Sort BEFORE rotating so the cycle runs over a stable set (the directory's order is itself
        // alphabetical, but sorting makes the rotation independent of how the directory happens to
        // be ordered). `arranged` stays pure — only the order handed to it changes, so slot counts
        // and cross-club balance are untouched.
        let rotatedClubs = ContentRoundRobin.rotate(
            followedClubs(following).map(\.abbreviation).sorted(), by: clubRotation)
        return Self.arranged(filtered, followedAbbreviations: rotatedClubs)
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

    /// Third-party voices go stale fast: reporter / league / news cards older than 30 days
    /// are dropped. A user's OWN followed content — club + player posts — is age-agnostic
    /// (a club's announcements have a long shelf life, and a quiet week shouldn't blank the
    /// feed). Static + `now`-injected so it unit-tests deterministically.
    static let thirdPartyMaxAge: TimeInterval = 30 * 24 * 60 * 60   // 30 days

    static func isFresh(_ card: ContentCard, now: Date) -> Bool {
        switch card.resolvedSourceType {
        case .reporter, .league, .news:
            return now.timeIntervalSince(card.timestamp) <= thirdPartyMaxAge
        case .club, .player:
            return true
        }
    }

    /// Base scope: a Feed-eligible card that's either league-wide or about a
    /// followed team. (Home-only cards never appear in the Feed.)
    private func isRelevant(_ card: ContentCard, _ followed: Set<String>) -> Bool {
        guard card.placement != .home else { return false }
        // Club Bluesky is retired from Social (the CLUBS chip is gone, 2026-08) — drop any
        // club cards so they never appear under All either, even before the proxy stops
        // fanning them out. The official club voice lives on Home Club News.
        if card.resolvedSourceType == .club { return false }
        if card.isLeague { return true }
        if let abbr = card.teamAbbreviation { return followed.contains(abbr) }
        return false
    }

    /// The chip → which source classes it admits, keyed off `resolvedSourceType`.
    /// Reporters covers BOTH `reporter` (Bluesky beat writers) AND `news` (curated-outlet
    /// articles) — the same journalist voice in two formats. `league` posts have no chip;
    /// they surface only under All.
    private func passesFilter(_ card: ContentCard) -> Bool {
        switch selectedFilter {
        case .all:       return true
        case .reporters: return card.resolvedSourceType == .reporter || card.resolvedSourceType == .news
        case .players:   return card.resolvedSourceType == .player
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

    /// Honor the user's player follows (Phase 3): an own-team player turned OFF is dropped; a
    /// cross-team player appears only if explicitly followed (the proxy already serves only the
    /// followed cross-team players, so this chiefly enforces the own-team opt-outs). Non-player
    /// cards always pass. A player's id is the card's `@<ig>` handle.
    private func passesPlayerFollow(_ card: ContentCard, _ followed: Set<String>, _ prefs: FeedPreferencesStore) -> Bool {
        guard card.resolvedSourceType == .player else { return true }
        guard let id = card.handle.map({ $0.hasPrefix("@") ? String($0.dropFirst()) : $0 })?.lowercased(),
              !id.isEmpty else { return true }
        let isOwnTeam = card.teamAbbreviation.map { followed.contains($0) } ?? false
        return prefs.isPlayerFollowed(id, isOwnTeam: isOwnTeam)
    }

    /// The distinct sources powering the Feed, alphabetical — for the mute list. User-added
    /// reporters are flagged (`isAdded`) and unioned in even when they have no current posts,
    /// so they always appear in Sources (Phase 3).
    func sources(_ preferences: FeedPreferencesStore) -> [Source] {
        let addedHandles = Set(preferences.addedReporters.map { "@" + $0.handle })
        var seen = Set<String>()
        var result: [Source] = []
        for item in allItems {
            let key = item.muteKey
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            let detail = item.handle ?? item.sourceName ?? item.platform.rawValue.capitalized
            let isAdded = item.handle.map { addedHandles.contains($0) } ?? false
            result.append(Source(name: key, detail: detail, isAdded: isAdded))
        }
        // Union any added reporters that have no current posts, so they still show in Sources.
        for r in preferences.addedReporters {
            let handleAt = "@" + r.handle
            if !result.contains(where: { $0.detail == handleAt || $0.name == r.displayName }) {
                result.append(Source(name: r.displayName, detail: handleAt, isAdded: true))
            }
        }
        return result.sorted { $0.name < $1.name }
    }
}
