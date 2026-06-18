//
//  FeedStore.swift
//  NWSLApp
//
//  Shared owner of the Feed's cards + load state, so the Feed can be PREWARMED before the
//  user ever opens the tab. Feed is the known-slow path (the proxy `/feed` route does
//  server-side Haiku team-tagging), so RootTabView kicks a low-priority prewarm after the
//  launch critical path settles; by the time the user switches to Feed the cards are usually
//  already loaded and the switch is instant. FeedView/FeedViewModel read this store (one fetch,
//  many readers — same pattern as MatchStore/ClubStore).
//
//  Online-only: a failed fetch sets `itemsError` (the view shows "Couldn't load — tap to
//  retry"), never stale/seed. `isLoadingItems` + `hasCompletedItemsLoad` let the view show an
//  honest loading state and the genuinely-empty copy ONLY after a load actually completes empty
//  — a loading state must never look identical to success (no silent failures).
//

import Foundation

@MainActor
@Observable
final class FeedStore {
    private(set) var allItems: [ContentCard] = []
    private(set) var itemsError: String? = nil
    private(set) var isLoadingItems: Bool = false
    private(set) var hasCompletedItemsLoad: Bool = false

    /// The one simple, honest message a failed Feed load shows.
    static let loadFailureMessage = "Couldn't load — tap to retry"

    private let contentService: ContentService

    init(contentService: ContentService = ContentService()) {
        self.contentService = contentService
    }

    /// Load once if not already loaded (and not currently loading or in an error state). The
    /// prewarm and the view's first-appearance both call this; whichever runs first wins, the
    /// other is a cheap no-op. Callers ensure `clubStore` is loaded first (for the scoping).
    func loadIfNeeded(following: FollowingStore, clubStore: ClubStore) async {
        guard allItems.isEmpty, itemsError == nil, !isLoadingItems else { return }
        await fetch(following: following, clubStore: clubStore)
    }

    /// Force a (re)load — pull-to-refresh + retry. Clears a prior error so the view shows the
    /// loading state, not the stale error.
    func load(following: FollowingStore, clubStore: ClubStore) async {
        guard !isLoadingItems else { return }
        itemsError = nil
        await fetch(following: following, clubStore: clubStore)
    }

    private func fetch(following: FollowingStore, clubStore: ClubStore) async {
        isLoadingItems = true
        defer { isLoadingItems = false; hasCompletedItemsLoad = true }
        // Scope the live `/feed` query to the followed clubs' team posts (the proxy returns
        // reporters + league regardless). Empty → reporters + league only.
        let followed = Set(
            clubStore.clubs
                .filter { following.followedIDs.contains($0.id) }
                .map(\.abbreviation)
        )
        do {
            allItems = try await contentService.feedCards(followedAbbreviations: followed)
                .sorted { $0.timestamp > $1.timestamp }
            itemsError = nil
        } catch {
            allItems = []
            itemsError = Self.loadFailureMessage
        }
    }
}
