//
//  HomeViewModel.swift
//  NWSLApp
//
//  Owns the Home tab's state and DERIVES its modules from data the app already
//  has — it does not own a second copy of the season. Like ScheduleViewModel,
//  it reads the shared MatchStore (handed in by the view) rather than fetching
//  the scoreboard itself. It fetches the club directory (FollowingStore stores
//  IDs only, so Home needs full Clubs with crests/names) and loads two TEMP
//  static content seeds for the content-led modules.
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
    // Same idle/loading/loaded/error shape as the other view models — here it
    // tracks the CLUB DIRECTORY fetch specifically (the season's load state lives
    // on the shared MatchStore; the content seeds load alongside it).
    enum State {
        case idle
        case loading
        case loaded([Club])
        case error(String)
    }

    private(set) var clubsState: State = .idle

    // Module 1/2 content (TEMP static seeds; see the providers). Loaded in
    // loadClubs() so they're ready by the time clubsState is .loaded.
    private(set) var teamContentItems: [TeamContentItem] = []
    // Named `allSpotlights` (not `spotlights`) so it doesn't collide with the
    // derived `spotlights(following:)` below.
    private(set) var allSpotlights: [PlayerSpotlight] = []

    // The shared season store, handed in by the view (mirrors ScheduleViewModel):
    // Home derives its modules from the same events Schedule renders, instead of
    // re-downloading ~240 events.
    var store: MatchStore?

    private let service: ESPNService
    private let contentProvider: TeamContentProvider
    private let spotlightProvider: PlayerSpotlightProvider
    private let calendar: Calendar
    private let now: () -> Date

    init(
        service: ESPNService = ESPNService(),
        contentProvider: TeamContentProvider = TeamContentProvider(),
        spotlightProvider: PlayerSpotlightProvider = PlayerSpotlightProvider(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.service = service
        self.contentProvider = contentProvider
        self.spotlightProvider = spotlightProvider
        self.calendar = calendar
        self.now = now
    }

    /// Loads the club directory plus the (TEMP) content seeds. Named for its
    /// primary job — resolving followed IDs → Clubs — but also pulls Module 1/2
    /// content so the whole hub is ready in one pass.
    func loadClubs() async {
        clubsState = .loading
        // Seeds resolve immediately today; the async shape is the future source's.
        teamContentItems = await contentProvider.items()
        allSpotlights = await spotlightProvider.spotlights()
        do {
            let clubs = try await service.fetchTeams()
            clubsState = .loaded(clubs)
        } catch {
            clubsState = .error(message(for: error))
        }
    }

    /// The loaded club directory (empty unless we're in `.loaded`).
    var clubs: [Club] {
        if case .loaded(let clubs) = clubsState { return clubs }
        return []
    }

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

    /// The latest team-content items across all followed clubs, newest first,
    /// capped so the hook stays scannable above the rest of the hub.
    func teamContent(following: FollowingStore, limit: Int = 6) -> [TeamContentItem] {
        let followed = followedAbbreviations(following)
        return teamContentItems
            .filter { followed.contains($0.teamAbbreviation) }
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

    private func message(for error: Error) -> String {
        switch error {
        case ESPNServiceError.badStatus(let code):
            return "ESPN returned an error (status \(code)). Pull to retry."
        case ESPNServiceError.decoding:
            return "Couldn't read the teams response. Pull to retry."
        case ESPNServiceError.badURL:
            return "Couldn't build the request. This is a bug — please report it."
        default:
            return "Couldn't load Home. Check your connection and pull to retry."
        }
    }
}
