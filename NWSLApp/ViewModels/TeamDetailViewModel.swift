//
//  TeamDetailViewModel.swift
//  NWSLApp
//
//  Owns state for TeamDetailView's *roster* fetch only. The club's matches come
//  from the shared MatchStore (already loaded for Schedule), so this view model
//  is responsible solely for loading and grouping the squad — keeping the same
//  idle/loading/loaded/error State enum the other screens use.
//

import Foundation

@Observable
final class TeamDetailViewModel {
    enum State {
        case idle
        case loading
        case loaded([Athlete])
        case error(String)
    }

    private(set) var state: State = .idle

    private let service: ESPNService

    init(service: ESPNService = ESPNService()) {
        self.service = service
    }

    func load(clubID: String) async {
        state = .loading
        do {
            let roster = try await service.fetchRoster(clubID: clubID)
            state = .loaded(roster)
        } catch {
            state = .error(message(for: error))
        }
    }

    /// The squad grouped by position (GK → DEF → MID → FWD); empty unless loaded.
    var positionGroups: [Roster.PositionGroup] {
        if case .loaded(let athletes) = state { return Roster.grouped(athletes) }
        return []
    }

    private func message(for error: Error) -> String {
        switch error {
        case ESPNServiceError.badStatus(let code):
            return "ESPN returned an error (status \(code))."
        case ESPNServiceError.decoding:
            return "Couldn't read the roster response."
        case ESPNServiceError.badURL:
            return "Couldn't build the request. This is a bug — please report it."
        default:
            return "Couldn't load the roster. Check your connection."
        }
    }
}
