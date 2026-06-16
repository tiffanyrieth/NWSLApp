//
//  MatchStore.swift
//  NWSLApp
//
//  The season's matches, fetched once and shared app-wide. Like FollowingStore,
//  this lives in Stores/ (not ViewModels/) and is injected via `.environment`
//  because more than one screen needs the same full-season event list: Schedule
//  renders all of it, a club's Team page renders its slice, and the future
//  your-teams-first Home will lead with followed clubs' next match. One fetch,
//  many readers — rather than each screen re-downloading ~240 events.
//
//  This is also the seam a future caching proxy/back end slots behind: today it
//  calls ESPN directly; later "one source of match data" can be served from a
//  server that polls ESPN once and fans out (see Reference/Sessions notes).
//

import Foundation

@Observable
final class MatchStore {
    // Same idle/loading/loaded/error shape the ViewModels use, so every async
    // fetch in the app models its outcomes identically.
    enum State {
        case idle
        case loading
        // Tagged with each match's competition (NWSL today; non-NWSL feeds merge in
        // here in later phases). Readers that only want raw events use `events`.
        case loaded([ScheduledMatch])
        case error(String)
    }

    private(set) var state: State = .idle

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

    // Always refetches (so pull-to-refresh works). "Load once" is the caller's
    // job — screens guard on `.idle` before kicking the first load, mirroring
    // TeamsView, so revisiting a tab doesn't refetch.
    func load() async {
        state = .loading
        let year = calendar.component(.year, from: now())
        do {
            let board = try await service.fetchScoreboard(year: year)
            // Tag every NWSL event with `.nwsl` (the spine). Non-NWSL competition
            // feeds merge into this list in later phases.
            state = .loaded(board.events.map { ScheduledMatch(event: $0, competition: .nwsl) })
        } catch {
            state = .error(message(for: error))
        }
    }

    /// The loaded season as tagged matches (empty unless we're in `.loaded`).
    var matches: [ScheduledMatch] {
        if case .loaded(let matches) = state { return matches }
        return []
    }

    /// The loaded season as raw events — the shape existing readers (Schedule,
    /// Home, Standings' Last-5, `matches(for:)`) already use. Derived from `matches`.
    var events: [Event] { matches.map(\.event) }

    // TEMP (fragile join): we match a club to its matches by `abbreviation`
    // because ESPN's scoreboard competitor `Team` carries no id (only the
    // `/teams` Club does). Verified in-sim that all 16 clubs' abbreviations are
    // identical across both endpoints, so this works today — but an abbreviation
    // rename (relocation/rebrand) would silently empty a club's schedule. Real
    // fix when we have a back end: a normalized club-id map, or a proxy that
    // attaches a stable id to every competitor. Until then the Team page shows a
    // visible empty state rather than failing silently.
    func matches(for club: Club) -> [Event] {
        let clubMatches = events.filter { event in
            event.homeCompetitor?.team?.abbreviation == club.abbreviation
                || event.awayCompetitor?.team?.abbreviation == club.abbreviation
        }
        return clubMatches.sorted { ($0.kickoff ?? .distantFuture) < ($1.kickoff ?? .distantFuture) }
    }

    private func message(for error: Error) -> String {
        switch error {
        case ESPNServiceError.badStatus(let code):
            return "ESPN returned an error (status \(code)). Pull to retry."
        case ESPNServiceError.decoding:
            return "Couldn't read the schedule response. Pull to retry."
        case ESPNServiceError.badURL:
            return "Couldn't build the request. This is a bug — please report it."
        default:
            return "Couldn't load the schedule. Check your connection and pull to retry."
        }
    }
}
