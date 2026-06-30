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
//  SCOPE-AWARE (same fix as HomeContentStore): the load reflects a followed-abbreviation set
//  (`loadedScope`). The launch prewarm can run BEFORE FollowSyncCoordinator restores the user's
//  server follows, so it would fetch an empty (reporters + league only) scope and latch it; a
//  plain `allItems.isEmpty` guard then no-op'd the tab's own load and the team sources never
//  appeared until a manual refresh. Tracking the scope lets the tab's `loadIfNeeded` notice the
//  follows arrived (scope changed) and refetch, while still sharing one fetch with the prewarm
//  when the scope didn't change.
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

    /// The followed-abbreviation set `allItems` currently reflects. nil = never loaded. Set
    /// ONLY on a successful fetch, so a failed/empty load doesn't latch as "loaded for this
    /// scope" (the next explicit retry refetches instead of no-op'ing).
    private var loadedScope: Set<String>? = nil

    private let contentService: ContentService

    init(contentService: ContentService = ContentService()) {
        self.contentService = contentService
    }

    /// Load if the followed-team scope hasn't been loaded yet (and there's no error to retry
    /// and no fetch in flight). The prewarm and the view's first-appearance both call this;
    /// whichever runs first wins, the other is a cheap no-op — UNLESS the follows changed since
    /// (e.g. the prewarm ran before the sign-in restore), in which case the scope no longer
    /// matches and this refetches. A prior error waits for the explicit "tap to retry" (`load`),
    /// not an auto-retry on every reappearance.
    func loadIfNeeded(following: FollowingStore, clubStore: ClubStore) async {
        let scope = await resolveScope(following: following, clubStore: clubStore)
        guard itemsError == nil else { return }
        guard loadedScope != scope, !isLoadingItems else { return }
        await fetch(scope: scope)
    }

    /// Force a (re)load — pull-to-refresh + retry. Clears a prior error so the view shows the
    /// loading state, not the stale error.
    func load(following: FollowingStore, clubStore: ClubStore) async {
        guard !isLoadingItems else { return }
        itemsError = nil
        let scope = await resolveScope(following: following, clubStore: clubStore)
        await fetch(scope: scope)
    }

    /// The followed-club abbreviations to scope the live `/feed` query to (the proxy returns
    /// reporters + league regardless; empty → reporters + league only). MUST wait for the club
    /// directory first — scoping before it's loaded yields an empty team set (the documented
    /// race). Dedupe-aware, so a no-op once loaded.
    private func resolveScope(following: FollowingStore, clubStore: ClubStore) async -> Set<String> {
        await clubStore.loadIfNeeded()
        return Set(
            clubStore.clubs
                .filter { following.followedIDs.contains($0.id) }
                .map(\.abbreviation)
        )
    }

    private func fetch(scope: Set<String>) async {
        isLoadingItems = true
        defer { isLoadingItems = false; hasCompletedItemsLoad = true }
        do {
            allItems = try await contentService.feedCards(followedAbbreviations: scope)
                .sorted { $0.timestamp > $1.timestamp }
            itemsError = nil
            // Latch only on success, so an errored load doesn't read as "loaded for this scope".
            loadedScope = scope
        } catch {
            Diagnostics.shared.record(.apiFailure, "feed load (\(scope.count) team(s)): \(error.localizedDescription)")
            allItems = []
            itemsError = Self.loadFailureMessage
        }
    }
}
