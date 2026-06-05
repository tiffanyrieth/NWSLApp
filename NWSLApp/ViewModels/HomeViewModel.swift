//
//  HomeViewModel.swift
//  NWSLApp
//
//  Owns the Home tab's state and DERIVES its modules from data the app already
//  has — it does not own a second copy of the season. Like ScheduleViewModel,
//  it reads the shared MatchStore (handed in by the view) rather than fetching
//  the scoreboard itself; the one thing it does fetch is the club directory,
//  because Home needs to resolve followed club IDs (FollowingStore stores IDs
//  only) into full Clubs with crests and names.
//
//  Home keys every module off the Following lens:
//   • Module 1 "Your next matches" — for each followed club, its next upcoming
//     match (or, if the season's done for them, their most recent result).
//   • Module 5 "Around the league" — the next matchday's games league-wide.
//  (Modules 2/3 are intentional placeholders in the view; Module 4 is opt-in
//  and not shown — see the design spec.)
//

import Foundation

@Observable
final class HomeViewModel {
    // Same idle/loading/loaded/error shape as the other view models — here it
    // tracks the CLUB DIRECTORY fetch specifically (the season's load state
    // lives on the shared MatchStore).
    enum State {
        case idle
        case loading
        case loaded([Club])
        case error(String)
    }

    private(set) var clubsState: State = .idle

    // The shared season store, handed in by the view (mirrors ScheduleViewModel):
    // Home derives its modules from the same events Schedule renders, instead of
    // re-downloading ~240 events.
    var store: MatchStore?

    private let service: ESPNService
    private let calendar: Calendar
    private let now: () -> Date

    init(
        service: ESPNService = ESPNService(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.service = service
        self.calendar = calendar
        self.now = now
    }

    func loadClubs() async {
        clubsState = .loading
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

    // MARK: - Module 1: Your next matches

    /// One followed club's match to surface on Home, with a display label and a
    /// flag for whether it's an upcoming fixture or a fallback recent result.
    struct FollowedFixture: Identifiable {
        let club: Club
        let event: Event
        let label: String      // "TODAY" / "TOMORROW" / "SAT, JUL 12"
        let isResult: Bool      // true → no upcoming match, showing latest result
        var id: String { club.id }
    }

    /// For each followed club: its next non-final match (preferred), else its
    /// most recent finished result so the card is never empty. Upcoming fixtures
    /// sort first (soonest kickoff), recent results last.
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

    // MARK: - Module 5: Around the league (next matchday)

    /// The next matchday's games league-wide: the earliest local day that still
    /// has a non-final match, and every game sharing that day. NWSL's staggered
    /// weekend slate keeps this a small, glanceable list.
    var aroundTheLeague: [Event] {
        guard let store else { return [] }
        let upcoming = store.events
            .filter { $0.statusState != "post" }
            .sorted { ($0.kickoff ?? .distantFuture) < ($1.kickoff ?? .distantFuture) }
        guard let firstDay = upcoming.first?.dayKey else { return [] }
        return upcoming.filter { $0.dayKey == firstDay }
    }

    /// Display label for the next matchday ("TODAY" / "SAT, JUL 12").
    var aroundTheLeagueLabel: String {
        dayLabel(for: aroundTheLeague.first?.kickoff, result: false)
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
