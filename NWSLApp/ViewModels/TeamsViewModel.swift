//
//  TeamsViewModel.swift
//  NWSLApp
//
//  Owns state for TeamsView: fetches the league's club directory. Uses the
//  same idle/loading/loaded/error State enum as ScheduleViewModel so both
//  screens model "async fetch with all its outcomes" the same way.
//

import Foundation

@Observable
final class TeamsViewModel {
    enum State {
        case idle
        case loading
        case loaded([Club])
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
            let clubs = try await service.fetchTeams()
            state = .loaded(clubs)
        } catch {
            state = .error(message(for: error))
        }
    }

    /// The loaded clubs (empty unless we're in `.loaded`).
    var clubs: [Club] {
        if case .loaded(let clubs) = state { return clubs }
        return []
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
            return "Couldn't load teams. Check your connection and pull to retry."
        }
    }
}
