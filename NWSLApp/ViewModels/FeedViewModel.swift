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

    // The shared club directory, handed in by the view (mirrors Home/Schedule):
    // used to scope the base set to followed teams. Until it's wired, `.idle`.
    var clubStore: ClubStore?

    private(set) var allItems: [ContentCard] = []
    var selectedFilter: ContentFilter = .all

    /// Online-only: a failed `/feed` fetch sets this honest message (the view shows
    /// "Couldn't load — tap to retry") instead of silently serving stale/seed content.
    private(set) var itemsError: String? = nil

    /// True while a `/feed` fetch is in flight; `hasCompletedItemsLoad` flips true the first time
    /// a fetch finishes (success OR failure). Together they let the view show the genuinely-empty
    /// "No posts yet" copy ONLY after a load has actually completed empty — never during loading,
    /// which must look different from success (no silent failures). `hasCompletedItemsLoad`
    /// defaults false so the whole first-load window (incl. the directory-load → items-load gap,
    /// where the directory is usually already warmed by Home, the landing tab) reads as loading,
    /// not a fake-empty.
    private(set) var isLoadingItems: Bool = false
    private(set) var hasCompletedItemsLoad: Bool = false

    /// The one simple, honest message a failed Feed load shows.
    static let loadFailureMessage = "Couldn't load — tap to retry"

    private let contentService: ContentService

    init(contentService: ContentService = ContentService()) {
        self.contentService = contentService
    }

    /// Proxies the shared club store's state so the view's error/ready checks over
    /// idle/loading/loaded/error are unchanged.
    var clubsState: ClubStore.State { clubStore?.state ?? .idle }

    /// (Re)load the shared directory, then the Feed cards. Used by pull-to-refresh.
    /// The directory loads first so `followedAbbreviations` is current (it scopes
    /// the live `/feed` query to the followed clubs' team posts).
    func load(following: FollowingStore) async {
        isLoadingItems = true
        itemsError = nil                 // clear so a retry shows the loading state, not the stale error
        defer { isLoadingItems = false; hasCompletedItemsLoad = true }
        await clubStore?.load()
        do {
            allItems = try await contentService.feedCards(
                followedAbbreviations: followedAbbreviations(following)
            ).sorted { $0.timestamp > $1.timestamp }
            itemsError = nil
        } catch {
            allItems = []
            itemsError = Self.loadFailureMessage
        }
    }

    /// Loads the Feed cards if not already loaded. Callers load the shared ClubStore
    /// first (so `followedAbbreviations` resolves) — kept separate from the directory
    /// load so the Feed still populates when another tab (Home, the landing tab)
    /// already loaded the directory.
    func loadItemsIfNeeded(following: FollowingStore) async {
        // First load only. After an error the view's "tap to retry" calls `load()`
        // directly, so don't auto-refetch here on a set error.
        guard allItems.isEmpty, itemsError == nil else { return }
        isLoadingItems = true
        defer { isLoadingItems = false; hasCompletedItemsLoad = true }
        do {
            allItems = try await contentService.feedCards(
                followedAbbreviations: followedAbbreviations(following)
            ).sorted { $0.timestamp > $1.timestamp }
            itemsError = nil
        } catch {
            allItems = []
            itemsError = Self.loadFailureMessage
        }
    }

    /// Abbreviations of the followed clubs — scopes the live `/feed` query (the
    /// proxy returns reporters + league regardless, plus team posts for these
    /// clubs). Empty (directory not loaded / no follows) → reporters + league only.
    private func followedAbbreviations(_ following: FollowingStore) -> Set<String> {
        Set(followedClubs(following).map(\.abbreviation))
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

    /// The chip → which source classes it admits, keyed off `sourceType(of:)`.
    /// Reporters also covers `league` (NWSL media/league-outlet social accounts).
    private func passesFilter(_ card: ContentCard) -> Bool {
        switch selectedFilter {
        case .all:       return true
        case .news:      return sourceType(of: card) == .news
        case .clubs:     return sourceType(of: card) == .club
        case .reporters: return sourceType(of: card) == .reporter || sourceType(of: card) == .league
        case .players:   return sourceType(of: card) == .player
        }
    }

    /// The card's source class: the proxy-set `sourceType` when present, else
    /// inferred from `layout` (seed/older cards, and player IG cards from a cron
    /// snapshot built before the proxy emitted `sourceType`). On the Feed,
    /// socialVideo/IG is a player clip (club social is placement "home").
    private func sourceType(of card: ContentCard) -> ContentCard.SourceType {
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
