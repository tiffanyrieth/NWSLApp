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
//  The filter chips are CONTENT-TYPE, not per-team (All / News / Social). The Feed
//  is the league-wide "soccer conversation" — content is already scoped by the
//  user's follows, so team chips would over-filter; team-specific content lives on
//  Home. The chip then narrows by card layout.
//
//  Filtering, in order:
//   1. Base — placement != .home, AND (about a followed team OR league-wide).
//   2. Chip — All / News (newsArticle) / Social (every individual voice: reporter
//      Bluesky + club Bluesky + player IG/TikTok clips). "Social" absorbs the old
//      "Reporters" chip (B3a); player IG/TikTok arrive live in B3b.
//   3. Preferences — drop muted sources + toggled-off content types.
//   4. Staleness (≤7 days) + reverse-chronological.
//

import Foundation

@Observable
final class FeedViewModel {
    /// The Feed's content-type filter (the chip bar). Replaces the old per-team
    /// chips — see the file note.
    enum ContentFilter: String, CaseIterable, Hashable {
        case all, news, social

        var label: String {
            switch self {
            case .all:    return "All"
            case .news:   return "News"
            case .social: return "Social"
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
        await clubStore?.load()
        allItems = (await contentService.feedCards(
            followedAbbreviations: followedAbbreviations(following)
        )).sorted { $0.timestamp > $1.timestamp }
    }

    /// Loads the Feed cards if not already loaded. Callers load the shared ClubStore
    /// first (so `followedAbbreviations` resolves) — kept separate from the directory
    /// load so the Feed still populates when another tab (Home, the landing tab)
    /// already loaded the directory.
    func loadItemsIfNeeded(following: FollowingStore) async {
        guard allItems.isEmpty else { return }
        allItems = (await contentService.feedCards(
            followedAbbreviations: followedAbbreviations(following)
        )).sorted { $0.timestamp > $1.timestamp }
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

    /// The content-type chip → which layouts it admits. "Social" is the home for
    /// every individual/conversational voice — reporter Bluesky, club Bluesky, and
    /// player IG/TikTok clips (the last arrive live in B3b).
    private func passesFilter(_ card: ContentCard) -> Bool {
        switch selectedFilter {
        case .all:    return true
        case .news:   return card.layout == .newsArticle
        case .social:
            switch card.layout {
            case .blueskyReporter, .blueskyTeamText, .blueskyTeamMedia,
                 .socialVideo, .instagramFallback:
                return true
            default:
                return false
            }
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
