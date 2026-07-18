//
//  StandingsViewModel.swift
//  NWSLApp
//
//  Owns state for StandingsView: fetches the league table. Uses the same
//  idle/loading/loaded/error State enum as Teams/Schedule so every async-fetch
//  screen models its outcomes identically.
//
//  Unlike the schedule (which reads the shared MatchStore), standings is its
//  own one-shot fetch with no other readers, so a per-screen ViewModel is the
//  right home for it — not an app-wide Store.
//

import Foundation

@Observable
final class StandingsViewModel {
    enum State {
        case idle
        case loading
        case loaded([StandingsRow])
        case error(String)
    }

    private(set) var state: State = .idle

    /// The season the loaded table actually represents. Owner rule: the Standings tab keeps the PRIOR
    /// season's FINAL table until the new season's first regular-season game kicks off, so this can lag
    /// the calendar year through the Nov→Mar offseason. Drives the header label (never mislabels the gap).
    private(set) var servedSeason: Int = Calendar.current.component(.year, from: Date())

    private let service: ESPNService

    init(service: ESPNService = ESPNService()) {
        self.service = service
    }

    func load() async {
        state = .loading
        let currentYear = Calendar.current.component(.year, from: Date())
        do {
            // SEASON ROLLOVER (owner rule): keep the PRIOR season's FINAL table until the NEW season's
            // FIRST regular-season game kicks off — so the tab is never a blank/half-broken table in the
            // Nov→Mar gap. (The Schedule rolls over at schedule-ANNOUNCE; Standings resets later, at first
            // KICKOFF.) "Started" = at least one team has played a game (gamesPlayed > 0), proven via ESPN's
            // per-season standings (`?season=`; a completed season returns a full table with GP > 0).
            let current = try await service.fetchStandings(season: currentYear)
            if current.contains(where: { $0.gamesPlayed > 0 }) {
                servedSeason = currentYear
                state = .loaded(current)
                return
            }
            // New season hasn't kicked off yet → serve the prior season's completed table. LOUD via diag
            // (like MatchStore's rollover) so an UNEXPECTED mid-season empty response is visible, not silent.
            let prior = try await service.fetchStandings(season: currentYear - 1)
            if prior.contains(where: { $0.gamesPlayed > 0 }) {
                Diagnostics.shared.record(.staleServe,
                    "standings rollover: \(currentYear) not started — serving \(currentYear - 1) final table")
                servedSeason = currentYear - 1
                state = .loaded(prior)
                return
            }
            // Neither season has games (deep gap / ESPN glitch): show the current table as-is (may be
            // empty) rather than nothing — honest, and the header labels the season it represents.
            servedSeason = currentYear
            state = .loaded(current)
        } catch {
            Diagnostics.shared.record(.apiFailure, "standings load: \(error.localizedDescription)")
            state = .error(message(for: error))
        }
    }

    /// The loaded rows (empty unless we're in `.loaded`).
    var rows: [StandingsRow] {
        if case .loaded(let rows) = state { return rows }
        return []
    }

    private func message(for error: Error) -> String {
        switch error {
        case ESPNServiceError.badStatus(let code):
            return "ESPN returned an error (status \(code)). Pull to retry."
        case ESPNServiceError.decoding:
            return "Couldn't read the standings response. Pull to retry."
        case ESPNServiceError.badURL:
            return "Couldn't build the request. This is a bug — please report it."
        default:
            return "Couldn't load standings. Check your connection and pull to retry."
        }
    }
}
