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
    // Module 1/2 content (TEMP static seeds; see the providers). Loaded in
    // loadContent(), which the view runs alongside the shared store loads.
    private(set) var teamContentItems: [ContentCard] = []
    // Named `allSpotlights` (not `spotlights`) so it doesn't collide with the
    // derived `spotlights(following:)` below.
    private(set) var allSpotlights: [PlayerSpotlight] = []

    // The shared season + club stores, handed in by the view (mirrors
    // ScheduleViewModel): Home derives its modules from the same events Schedule
    // renders and the same directory Teams lists — no re-downloading.
    var store: MatchStore?
    var clubStore: ClubStore?

    private let contentService: ContentService
    private let spotlightProvider: PlayerSpotlightProvider
    private let calendar: Calendar
    private let now: () -> Date

    init(
        contentService: ContentService = ContentService(),
        spotlightProvider: PlayerSpotlightProvider = PlayerSpotlightProvider(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.contentService = contentService
        self.spotlightProvider = spotlightProvider
        self.calendar = calendar
        self.now = now
    }

    /// Loads Module-1 content via `ContentService` (live `/team-videos` once
    /// enabled; the Part-1 ⚠️seed today) plus the Module-2 spotlight seed. Runs
    /// AFTER the shared ClubStore so `followedAbbreviations` is resolvable (the
    /// live route is scoped to followed teams; the seed ignores the arg and returns
    /// all, leaving the per-follow filtering to `teamContent`).
    ///
    /// ⚠️ TEMP seam: idempotent on first load. Once `liveContentEnabled` is true,
    /// a newly-followed team's live content won't appear until a refresh because
    /// the guard skips a refetch (the seed is unaffected — it loads all + filters).
    /// Wire a refetch on follows-change when the live route lands (Part 2 Step 1).
    func loadContent(following: FollowingStore) async {
        guard teamContentItems.isEmpty else { return }
        teamContentItems = await contentService.homeCards(
            followedAbbreviations: followedAbbreviations(following)
        )
        allSpotlights = await spotlightProvider.spotlights()
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

    /// The latest team-content cards across all followed clubs, newest first,
    /// capped so the hook stays scannable above the rest of the hub. Home shows
    /// only the teams' OWN voices, so feed-only cards are gated out (placement),
    /// and only same-day-ish content survives the 72h Home staleness window.
    func teamContent(following: FollowingStore, limit: Int = 6) -> [ContentCard] {
        let followed = followedAbbreviations(following)
        return teamContentItems
            .filter { card in
                guard card.placement != .feed,
                      let abbr = card.teamAbbreviation else { return false }
                return followed.contains(abbr)
            }
            .fresh(.home, now: now())
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(limit)
            .map { $0 }
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
