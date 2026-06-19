//
//  HomeViewModel.swift
//  NWSLApp
//
//  Owns the Home tab's state and DERIVES its modules from data the app already
//  has — it does not own a second copy of the season. Like ScheduleViewModel,
//  it reads the shared MatchStore AND the shared ClubStore (both handed in by the
//  view) rather than fetching the scoreboard or the directory itself. It owns
//  only the two TEMP static content seeds for the content-led modules.
//
//  Home keys every module off the Following lens (new order per the updated
//  Reference/Design/home-tab-design-spec.md — content leads, schedule demoted):
//   • Module 1 "From your teams"          — team content items for followed clubs.
//   • Module 2 "Get to know your players" — one weekly player spotlight.
//   • Module 3 "Play"                     — placeholder (in the view).
//   • Module 4 "Coming up"                — compact next-match strip per club.
//  ("Around the league" was removed — it duplicated the Schedule tab.)
//

import Foundation

@Observable
final class HomeViewModel {
    // Module 1/2 live content, loaded in loadContent() alongside the shared store
    // loads. Online-only: a failed fetch sets the matching per-module error below
    // (and clears the items) so the module shows an honest "Couldn't load — tap to
    // retry" — never stale/seed content.
    private(set) var teamContentItems: [ContentCard] = []
    // Named `allSpotlights` (not `spotlights`) so it doesn't collide with the
    // derived `spotlights(following:)` below.
    private(set) var allSpotlights: [PlayerSpotlight] = []

    // Per-module load errors (Module 1 = content, Module 2 = spotlight). Each module
    // fails independently — one going down doesn't blank the other. nil = no error.
    private(set) var contentError: String? = nil
    private(set) var spotlightError: String? = nil

    // Module-1 load lifecycle, so the view can tell "still loading" from "loaded but
    // genuinely empty". Without it the empty/Retry card flashes for a frame during the
    // initial fetch — a loading state must never look identical to an empty result (#5).
    // Mirrors FeedStore's isLoadingItems + hasCompletedItemsLoad.
    private(set) var isLoadingContent = false
    private(set) var hasCompletedContentLoad = false

    /// The one simple, honest message both modules show on a failed load.
    static let loadFailureMessage = "Couldn't load — tap to retry"

    // The active PER-TEAM chip on Module 1 (chip redesign): nil = "All" (the mixed,
    // round-robin feed); else a followed team's abbreviation = just that club's
    // content. In-memory only — never persisted, reset to "All" on pull-to-refresh.
    var selectedTeam: String? = nil

    // Change 1: per-team rotation offsets for pull-to-refresh. In-memory (the spec
    // doesn't ask them to survive launches). Advanced when a refresh finds no new
    // content, so the user discovers cards they hadn't seen.
    private(set) var windowOffsets: [String: Int] = [:]

    // The shared season + club stores, handed in by the view (mirrors
    // ScheduleViewModel): Home derives its modules from the same events Schedule
    // renders and the same directory Teams lists — no re-downloading.
    var store: MatchStore?
    var clubStore: ClubStore?

    private let contentService: ContentService
    private let calendar: Calendar
    private let now: () -> Date

    init(
        contentService: ContentService = ContentService(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.contentService = contentService
        self.calendar = calendar
        self.now = now
    }

    /// Loads Module-1 content via `ContentService` (live `/team-videos` once
    /// enabled; the Part-1 ⚠️seed today) plus the Module-2 spotlight seed. Runs
    /// AFTER the shared ClubStore so `followedAbbreviations` is resolvable (the
    /// live route is scoped to followed teams; the seed ignores the arg and returns
    /// all, leaving the per-follow filtering to `teamContent`).
    ///
    /// `force == false` loads once (the first-open `.task`); `force == true` refetches
    /// (pull-to-refresh + a follows change), so a newly-followed team's content appears
    /// without relaunching. (Replaces the old idempotent-only TEMP guard.)
    func loadContent(following: FollowingStore, force: Bool = false) async {
        // Reload when forced, when nothing's loaded yet, or when a prior load errored
        // (so the per-module "tap to retry" actually retries).
        guard force || (teamContentItems.isEmpty && contentError == nil
                        && allSpotlights.isEmpty && spotlightError == nil) else { return }
        // Mark the module as loading BEFORE the first await so the view shows a loading
        // state (not the empty/Retry card) during the directory-load → content-load gap.
        // `hasCompletedContentLoad` latches true at the end and stays true across forced
        // refetches (those keep the existing cards on screen, so no flash).
        isLoadingContent = true
        defer { isLoadingContent = false; hasCompletedContentLoad = true }
        // CRITICAL: content is scoped to followed-team ABBREVIATIONS resolved from the club
        // directory, so we must not proceed until ClubStore is `.loaded`. Otherwise a prewarmed-
        // but-still-loading directory yields an empty scope → `/team-videos` with no `teams=` →
        // an empty Home feed (the race this fixes). Dedupe-aware, so it's a no-op once loaded.
        await clubStore?.loadIfNeeded()
        let followed = followedAbbreviations(following)
        // Module 1 (content) and Module 2 (spotlight) load + fail independently.
        do {
            var cards = try await contentService.homeCards(followedAbbreviations: followed)
            // A followed team returning ZERO cards is unexpected — content normally exists and
            // there's a 6-card floor — and it's intermittent (reproduced in-sim: same team,
            // empty on one run, populated on others → a transient/cold-proxy empty). Treat it as
            // a no-silent-failure event: flag it AND auto-retry once after a beat so it self-heals.
            if cards.isEmpty && !followed.isEmpty {
                await MainActor.run { Diagnostics.shared.record(.unexpectedEmpty, "home content empty for \(followed.count) team(s)") }
                try? await Task.sleep(for: .milliseconds(800))
                cards = try await contentService.homeCards(followedAbbreviations: followed)
                if cards.isEmpty {
                    await MainActor.run { Diagnostics.shared.record(.unexpectedEmpty, "home content still empty after retry (\(followed.count) team(s))") }
                }
            }
            teamContentItems = cards
            contentError = nil
        } catch {
            teamContentItems = []
            contentError = Self.loadFailureMessage
        }
        do {
            allSpotlights = try await contentService.spotlightCards(followedAbbreviations: followed)
            spotlightError = nil
        } catch {
            allSpotlights = []
            spotlightError = Self.loadFailureMessage
        }
    }

    /// Retry a failed content/spotlight load (the per-module "tap to retry"). Forces a
    /// refetch of both modules — they share the proxy, so one tap recovers both.
    func retryContent(following: FollowingStore) async {
        await loadContent(following: following, force: true)
    }

    /// Pull-to-refresh: refetch, reset the chip to All, then either lead with the new
    /// content (offsets cleared so newest surfaces) or — when nothing new arrived —
    /// advance the rotation window so the user still sees cards they hadn't seen.
    func refresh(following: FollowingStore) async {
        let previousIDs = Set(teamContentItems.map(\.id))
        await loadContent(following: following, force: true)
        selectedTeam = nil
        let newIDs = Set(teamContentItems.map(\.id))
        if newIDs == previousIDs {
            advanceRotation(following: following)
        } else {
            windowOffsets = [:]
        }
    }

    /// Shift each followed team's window forward by one page (`guaranteed`), wrapping,
    /// over its fresh content pool. Pure logic lives in ContentRoundRobin.
    private func advanceRotation(following: FollowingStore) {
        let ordered = orderedFollowedAbbreviations(following)
        var counts: [String: Int] = [:]
        for card in freshFollowedCards(following: following) {
            if let abbr = card.teamAbbreviation { counts[abbr, default: 0] += 1 }
        }
        let (guaranteed, _) = ContentRoundRobin.tier(ordered.count)
        windowOffsets = ContentRoundRobin.advancedOffsets(
            current: windowOffsets,
            availableCounts: counts,
            guaranteed: guaranteed
        )
    }

    /// Proxies the shared club store's state so HomeView's error/ready checks over
    /// idle/loading/loaded/error are unchanged.
    var clubsState: ClubStore.State { clubStore?.state ?? .idle }

    /// The loaded club directory (empty unless the store is `.loaded`).
    var clubs: [Club] { clubStore?.clubs ?? [] }

    /// A followed club looked up by abbreviation — the join key content items and
    /// spotlights carry (ESPN gives no stable competitor id; mirrors MatchStore).
    func club(forAbbreviation abbreviation: String) -> Club? {
        clubs.first { $0.abbreviation == abbreviation }
    }

    /// Abbreviations of the clubs the user follows.
    private func followedAbbreviations(_ following: FollowingStore) -> Set<String> {
        Set(clubs.filter { following.followedIDs.contains($0.id) }.map(\.abbreviation))
    }

    // MARK: - Module 1: From your teams

    /// The "From your teams" module. On **All** (`selectedTeam == nil`): the
    /// round-robin fair-share across followed clubs (every team a guaranteed minimum,
    /// interleaved so a quiet club sits beside a loud one), capped by follow count.
    /// On a **per-team** chip: just that club's content, reverse-chron (balancing is
    /// moot for one team), capped the same so the module doesn't bury what's below.
    /// Returns the cards AND the overflow count (drives the "See more →" link).
    ///
    /// Returns a value (no stored state) so it's side-effect-free to call from `body`.
    func teamContent(following: FollowingStore) -> ContentRoundRobin.Result {
        let ordered = orderedFollowedAbbreviations(following)
        let fresh = freshFollowedCards(following: following)
        // Per-team chip (only honored if that team is still followed).
        if let team = selectedTeam, ordered.contains(team) {
            let cards = fresh
                .filter { $0.teamAbbreviation == team }
                .sorted { $0.timestamp > $1.timestamp }
            let cap = ContentRoundRobin.tier(ordered.count).cap
            return ContentRoundRobin.Result(cards: Array(cards.prefix(cap)),
                                            overflowCount: max(0, cards.count - cap))
        }
        return ContentRoundRobin.balanced(
            cards: fresh,
            followedAbbreviations: ordered,
            windowOffsets: windowOffsets
        )
    }

    /// Followed teams' own fresh cards (placement + follow + freshness) — the
    /// rotation pool and the per-team base. News articles get the longer 7-day window
    /// (the Feed's): club news posts a few times a week, so under the tight 72h window
    /// a 4-day-old article is buried by the day's clip flood and Home reads like a
    /// video channel (bug #4). Social/video keep the 72h window.
    private func freshFollowedCards(following: FollowingStore) -> [ContentCard] {
        let followed = followedAbbreviations(following)
        let owned = teamContentItems.filter { card in
            guard card.placement != .feed,
                  let abbr = card.teamAbbreviation else { return false }
            return followed.contains(abbr)
        }
        let news = owned.filter { $0.layout == .newsArticle }.fresh(.feed, now: now())
        let rest = owned.filter { $0.layout != .newsArticle }.fresh(.home, now: now())
        return news + rest
    }

    /// The full firehose for the "See more from your teams" screen: ALL followed-team
    /// content (no cap, no staleness floor, no round-robin), reverse-chron, honoring
    /// the active per-team chip.
    func allFollowedTeamContent(following: FollowingStore) -> [ContentCard] {
        let followed = followedAbbreviations(following)
        return teamContentItems
            .filter { card in
                guard card.placement != .feed,
                      let abbr = card.teamAbbreviation else { return false }
                guard followed.contains(abbr) else { return false }
                if let team = selectedTeam { return abbr == team }
                return true
            }
            .sorted { $0.timestamp > $1.timestamp }
    }

    /// Followed clubs' abbreviations in a STABLE (alphabetical) order — the
    /// deterministic interleave order the round-robin needs.
    private func orderedFollowedAbbreviations(_ following: FollowingStore) -> [String] {
        clubs
            .filter { following.followedIDs.contains($0.id) }
            .map(\.abbreviation)
            .sorted()
    }

    /// Followed clubs' abbreviations in the club directory's order — the order the
    /// per-team chips appear in (matches the Teams tab's Following list). "All" is
    /// prepended by the chip bar; this is just the team list.
    func followedTeamAbbreviations(following: FollowingStore) -> [String] {
        clubs
            .filter { following.followedIDs.contains($0.id) }
            .map(\.abbreviation)
    }

    /// Reset the per-team chip to All if its team is no longer followed (e.g. you
    /// unfollowed the team you were filtering to). Call when the followed set changes.
    func reconcileSelectedTeam(following: FollowingStore) {
        guard let team = selectedTeam else { return }
        if !followedTeamAbbreviations(following: following).contains(team) {
            selectedTeam = nil
        }
    }

    // MARK: - Module 2: Get to know your players

    /// One spotlight PER followed team (spec §Multi-team rotation): follow 2
    /// teams, see 2 cards. Each team rotates independently — a deterministic
    /// week-of-year pick over that team's spotlight list, so it's stable within a
    /// week and cycles through the roster as the seed grows (one player per team
    /// today → the pick is simply that player). Ordered by the followed clubs'
    /// directory order (alphabetical) for a stable layout.
    func spotlights(following: FollowingStore) -> [PlayerSpotlight] {
        let week = calendar.component(.weekOfYear, from: now())
        return clubs
            .filter { following.followedIDs.contains($0.id) }
            .compactMap { club in
                let forTeam = allSpotlights
                    .filter { $0.teamAbbreviation == club.abbreviation }
                    .sorted { $0.id < $1.id }   // stable order for the rotation
                guard !forTeam.isEmpty else { return nil }
                return forTeam[week % forTeam.count]
            }
    }

    // MARK: - Module 4: Coming up (compact next-match strip)

    /// One followed club's match to surface, with a display label and a flag for
    /// whether it's an upcoming fixture or a fallback recent result.
    struct FollowedFixture: Identifiable {
        let club: Club
        let event: Event
        let label: String      // "TODAY" / "TOMORROW" / "SAT, JUL 12"
        let isResult: Bool      // true → no upcoming match, showing latest result
        var id: String { club.id }
    }

    /// For each followed club: its next non-final match (preferred), else its most
    /// recent finished result so the row is never empty. Upcoming fixtures sort
    /// first (soonest kickoff), recent results last.
    func nextMatches(following: FollowingStore) -> [FollowedFixture] {
        guard let store else { return [] }
        let followed = clubs.filter { following.followedIDs.contains($0.id) }
        let fixtures = followed.compactMap { club -> FollowedFixture? in
            // matches(for:) returns this club's events sorted ascending by kickoff.
            let matches = store.matches(for: club)
            if let upcoming = matches.first(where: { $0.statusState != "post" }) {
                return FollowedFixture(
                    club: club, event: upcoming,
                    label: dayLabel(for: upcoming.kickoff, result: false),
                    isResult: false
                )
            }
            if let last = matches.last(where: { $0.statusState == "post" }) {
                return FollowedFixture(
                    club: club, event: last,
                    label: dayLabel(for: last.kickoff, result: true),
                    isResult: true
                )
            }
            return nil
        }
        return fixtures.sorted { a, b in
            if a.isResult != b.isResult { return !a.isResult }   // upcoming before results
            let ka = a.event.kickoff ?? .distantFuture
            let kb = b.event.kickoff ?? .distantFuture
            // Upcoming: soonest first. Results: most recent first.
            return a.isResult ? ka > kb : ka < kb
        }
    }

    // MARK: - Helpers

    /// Time-aware label: "TODAY"/"TOMORROW" for near fixtures, otherwise a short
    /// weekday + date. Results always use the date form (never "TODAY").
    private func dayLabel(for date: Date?, result: Bool) -> String {
        guard let date else { return result ? "RECENT" : "TBD" }
        if !result {
            if calendar.isDateInToday(date) { return "TODAY" }
            if calendar.isDateInTomorrow(date) { return "TOMORROW" }
        }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.calendar = calendar
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date).uppercased()
    }
}
