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

    private let service: ESPNService

    init(service: ESPNService = ESPNService()) {
        self.service = service
    }

    func load() async {
        state = .loading
        do {
            let rows = try await service.fetchStandings()
            state = .loaded(rows)
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
