//
//  HomeContentStore.swift
//  NWSLApp
//
//  Shared owner of the Home tab's ALIVE content — Module 1 ("From your teams":
//  team videos + club news + club IG) and Module 2 (the player Spotlight). It's the
//  Home twin of FeedStore: a shared, prewarmable store so the content can be fetched
//  BEFORE HomeView is ever on screen. Two callers warm it early:
//   • OnboardingView — the instant the user picks a team in "Make it yours", we warm
//     the content for the current selection (debounced), re-warming as they change it,
//     so Home is already populated when they tap "Follow N teams" (no first-paint flash).
//   • RootTabView — a low-priority prewarm on the already-onboarded launch path.
//  HomeViewModel reads the raw items from here and does ALL the derivation (round-robin,
//  staleness, per-team chip) — one fetch, many readers (same pattern as MatchStore/ClubStore).
//
//  SCOPE-AWARE: unlike FeedStore (which dedupes on `allItems.isEmpty`), this tracks the
//  followed-abbreviation set the current content reflects (`loadedScope`). A warm done for
//  the selection in progress is served instantly when Home appears IF the scope still
//  matches; if the user changed their picks after the last warm, the scope no longer matches
//  and Home's `loadIfNeeded` refetches. This lets the onboarding warm and the final Home load
//  share one fetch when the selection didn't change, and self-correct when it did.
//
//  Online-only: a failed fetch sets the matching per-module error (the view shows an honest
//  "Couldn't load — tap to retry"), never stale/seed. `isLoadingContent` + `hasCompletedContentLoad`
//  let the view show an honest loading state and the genuinely-empty copy ONLY after a load
//  actually completes — a loading state must never look identical to success (no silent failures).
//

import Foundation

@MainActor
@Observable
final class HomeContentStore {
    // Module 1 (content) + Module 2 (spotlight) raw items. Derivation (round-robin,
    // staleness, chip filtering) lives in HomeViewModel, which reads these.
    private(set) var teamContentItems: [ContentCard] = []
    private(set) var allSpotlights: [PlayerSpotlight] = []

    // Per-module load errors (each module fails independently — one going down doesn't
    // blank the other). nil = no error.
    private(set) var contentError: String? = nil
    private(set) var spotlightError: String? = nil

    // Load lifecycle, so the view can tell "still loading" from "loaded but genuinely
    // empty" — without it the empty/Retry card flashes for a frame during the initial
    // fetch (a loading state must never look identical to an empty result, #5).
    private(set) var isLoadingContent = false
    private(set) var hasCompletedContentLoad = false

    /// The one simple, honest message both modules show on a failed load.
    static let loadFailureMessage = "Couldn't load — tap to retry"

    // The followed-abbreviation set `teamContentItems`/`allSpotlights` currently reflect.
    // nil = never loaded. Set ONLY on a successful fetch, so a failed/empty load doesn't
    // latch as "loaded for this scope" (the next loadIfNeeded retries instead of no-op'ing).
    private var loadedScope: Set<String>? = nil

    // The store-owned debounce/cancel handle for warm(). Store-owned (not view-owned)
    // because the store outlives OnboardingView across the onboarding→Home flip, and so
    // loadIfNeeded can await an in-flight warm rather than start a parallel fetch.
    private var warmTask: Task<Void, Never>?

    private let contentService: ContentService

    init(contentService: ContentService = ContentService()) {
        self.contentService = contentService
    }

    // MARK: - Entry points

    /// Home's `.task` entry point. Serves the warmed content instantly when the scope still
    /// matches; otherwise (first load, or the selection changed since the warm) fetches. If a
    /// warm is mid-flight, awaits it rather than starting a parallel fetch (no interleaved writes).
    func loadIfNeeded(following: FollowingStore, clubStore: ClubStore) async {
        if isLoadingContent, let warmTask { await warmTask.value }
        await loadIfScopeChanged(following: following, clubStore: clubStore)
    }

    /// Force a (re)load — pull-to-refresh + the per-module "tap to retry". Clears prior errors
    /// so the view shows the loading state, not the stale error.
    func reload(following: FollowingStore, clubStore: ClubStore) async {
        guard !isLoadingContent else { return }
        contentError = nil
        spotlightError = nil
        let scope = await resolveScope(following: following, clubStore: clubStore)
        await fetch(scope: scope)
    }

    /// Onboarding entry point: warm the content for the CURRENT selection, debounced. Each call
    /// cancels the prior pending warm, so tapping through several teams coalesces into ONE fetch
    /// reflecting the final selection. Fire-and-forget (the view doesn't await it).
    func warm(following: FollowingStore, clubStore: ClubStore) {
        warmTask?.cancel()
        warmTask = Task { [weak self] in
            // Coalesce a burst of selections (the proxy `/team-videos` route is scoped by
            // `?teams=` and does real server-side work, so we don't want one request per tap).
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await self?.loadIfScopeChanged(following: following, clubStore: clubStore)
        }
    }

    // MARK: - Internals

    /// Resolve, then fetch only if the resolved scope differs from what's already loaded (and
    /// there's no error to retry). Shared by loadIfNeeded and warm.
    private func loadIfScopeChanged(following: FollowingStore, clubStore: ClubStore) async {
        let scope = await resolveScope(following: following, clubStore: clubStore)
        if loadedScope == scope, contentError == nil, spotlightError == nil { return }
        guard !isLoadingContent else { return }
        await fetch(scope: scope)
    }

    /// The followed-team abbreviations to scope the content to. MUST wait for the club directory
    /// first — scoping before it's loaded yields an empty set → `/team-videos` with no `teams=`
    /// → an empty Home feed (the documented race). Dedupe-aware, so a no-op once loaded.
    private func resolveScope(following: FollowingStore, clubStore: ClubStore) async -> Set<String> {
        await clubStore.loadIfNeeded()
        return Set(
            clubStore.clubs
                .filter { following.followedIDs.contains($0.id) }
                .map(\.abbreviation)
        )
    }

    /// Fetch Module 1 + Module 2 for an already-resolved scope. They load + fail independently.
    /// On success, latch `loadedScope` so a matching future load is an instant no-op.
    private func fetch(scope: Set<String>) async {
        isLoadingContent = true
        defer { isLoadingContent = false; hasCompletedContentLoad = true }
        var anySuccess = false
        // Module 1 (content).
        do {
            var cards = try await contentService.homeCards(followedAbbreviations: scope)
            // A followed team returning ZERO cards is unexpected — content normally exists and
            // there's a 6-card floor — and it's intermittent (reproduced in-sim: same team,
            // empty on one run, populated on others → a transient/cold-proxy empty). Treat it as
            // a no-silent-failure event: flag it AND auto-retry once after a beat so it self-heals.
            if cards.isEmpty && !scope.isEmpty {
                Diagnostics.shared.record(.unexpectedEmpty, "home content empty for \(scope.count) team(s)")
                try? await Task.sleep(for: .milliseconds(800))
                cards = try await contentService.homeCards(followedAbbreviations: scope)
                if cards.isEmpty {
                    Diagnostics.shared.record(.unexpectedEmpty, "home content still empty after retry (\(scope.count) team(s))")
                }
            }
            teamContentItems = cards
            contentError = nil
            anySuccess = true
        } catch {
            Diagnostics.shared.record(.apiFailure, "home content (\(scope.count) team(s)): \(error.localizedDescription)")
            teamContentItems = []
            contentError = Self.loadFailureMessage
        }
        // Module 2 (spotlight).
        do {
            allSpotlights = try await contentService.spotlightCards(followedAbbreviations: scope)
            spotlightError = nil
            anySuccess = true
        } catch {
            Diagnostics.shared.record(.apiFailure, "home spotlight (\(scope.count) team(s)): \(error.localizedDescription)")
            allSpotlights = []
            spotlightError = Self.loadFailureMessage
        }
        // Only latch the scope when at least one module actually loaded — so a fully-failed load
        // doesn't mark this scope "done" and suppress the next retry.
        if anySuccess { loadedScope = scope }
    }
}
