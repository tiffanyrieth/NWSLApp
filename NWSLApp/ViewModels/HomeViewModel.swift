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

@MainActor
@Observable
final class HomeViewModel {
    // Module 1/2 live content lives in the shared HomeContentStore (handed in by the view,
    // like `store`/`clubStore`), so it can be warmed during onboarding and prewarmed at
    // launch. HomeViewModel reads the raw items from it and does ALL the derivation below
    // (round-robin, staleness, per-team chip) — one fetch, many readers.
    var contentStore: HomeContentStore?

    // Passthroughs so the view's existing reads (error/loading state) are unchanged — the
    // store is the source of truth for the raw content + its load lifecycle.
    var contentError: String? { contentStore?.contentError }
    var spotlightError: String? { contentStore?.spotlightError }
    var isLoadingContent: Bool { contentStore?.isLoadingContent ?? false }
    var hasCompletedContentLoad: Bool { contentStore?.hasCompletedContentLoad ?? false }

    // Raw content the derivation methods read, sourced from the store (so those methods
    // are unchanged). Empty until the store has loaded.
    private var teamContentItems: [ContentCard] { contentStore?.teamContentItems ?? [] }
    private var allSpotlights: [PlayerSpotlight] { contentStore?.allSpotlights ?? [] }

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

    private let calendar: Calendar
    private let now: () -> Date

    init(
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.calendar = calendar
        self.now = now
    }

    /// Retry a failed content/spotlight load (the per-module "tap to retry"). Forces a
    /// refetch of both modules through the shared store — they share the proxy, so one
    /// tap recovers both.
    func retryContent(following: FollowingStore) async {
        guard let contentStore, let clubStore else { return }
        await contentStore.reload(following: following, clubStore: clubStore)
    }

    /// Pull-to-refresh: refetch, reset the chip to All, then either lead with the new
    /// content (offsets cleared so newest surfaces) or — when nothing new arrived —
    /// advance the rotation window so the user still sees cards they hadn't seen.
    func refresh(following: FollowingStore) async {
        guard let contentStore, let clubStore else { return }
        let previousIDs = Set(teamContentItems.map(\.id))
        await contentStore.reload(following: following, clubStore: clubStore)
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
        for card in followedTeamCards(following: following) {
            if let abbr = card.teamAbbreviation { counts[abbr, default: 0] += 1 }
        }
        let pageSize = ContentRoundRobin.homeSlotsPerClub(ordered.count)
        windowOffsets = ContentRoundRobin.advancedOffsets(
            current: windowOffsets,
            availableCounts: counts,
            pageSize: pageSize
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
    /// count-based, volume-blind round-robin across followed clubs (every club an equal
    /// slot allowance, interleaved so a quiet club sits beside a loud one — a chatty
    /// club can't crowd it out, and no time window applies). On a **per-team** chip:
    /// just that club's content, newest-first (balancing is moot for one club).
    /// Returns the cards AND the overflow count (drives the "See more →" link).
    ///
    /// Returns a value (no stored state) so it's side-effect-free to call from `body`.
    func teamContent(following: FollowingStore) -> ContentRoundRobin.Result {
        let ordered = orderedFollowedAbbreviations(following)
        let cards = followedTeamCards(following: following)
        // Per-team chip (only honored if that team is still followed): a focused
        // single-club view, so it uses the single-club allowance.
        if let team = selectedTeam, ordered.contains(team) {
            let teamCards = cards
                .filter { $0.teamAbbreviation == team }
                .sorted { $0.timestamp > $1.timestamp }
            let cap = ContentRoundRobin.homeSlotsPerClub(1)
            return ContentRoundRobin.Result(cards: Array(teamCards.prefix(cap)),
                                            overflowCount: max(0, teamCards.count - cap))
        }
        let balanced = ContentRoundRobin.balanced(
            cards: cards,
            followedAbbreviations: ordered,
            slotsPerClub: ContentRoundRobin.homeSlotsPerClub(ordered.count),
            windowOffsets: windowOffsets
        )
        // Cap the "All" preview at ~6–7 cards (design spec) so Spotlight + Fan Zone
        // aren't pushed below the fold; the remainder spills into the "See more club
        // news →" firehose via overflowCount. The per-team chip above is intentionally
        // NOT capped (it's the full single-club lens — Part B Bug 3a/5).
        guard balanced.cards.count > Self.homeAllCardCap else { return balanced }
        let dropped = balanced.cards.count - Self.homeAllCardCap
        return ContentRoundRobin.Result(
            cards: Array(balanced.cards.prefix(Self.homeAllCardCap)),
            overflowCount: balanced.overflowCount + dropped
        )
    }

    /// Max cards on Home's "All" content preview (design spec: 6–7). Overflow goes to
    /// the "See more club news →" firehose.
    private static let homeAllCardCap = 7

    /// Followed clubs' own Home cards (placement ≠ `.feed`, club ∈ follows) — the
    /// rotation pool and the per-team base. NO freshness filter: representation is
    /// count-based and age-agnostic, so `ContentRoundRobin.balanced` takes each club's
    /// most-recent posts regardless of age and `typeInterleaved` mixes news/video/social
    /// within a club's slots (so news isn't buried — no separate window needed).
    private func followedTeamCards(following: FollowingStore) -> [ContentCard] {
        let followed = followedAbbreviations(following)
        return teamContentItems.filter { card in
            guard card.placement != .feed,
                  let abbr = card.teamAbbreviation else { return false }
            return followed.contains(abbr)
        }
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
