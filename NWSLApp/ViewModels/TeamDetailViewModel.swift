//
//  TeamDetailViewModel.swift
//  NWSLApp
//
//  Owns state for TeamDetailView's roster fetch. One call to ESPN's roster
//  endpoint returns a ClubSquad — the players plus the team profile (color,
//  standing line) that rides along — so this view model feeds the whole page:
//  the position-grouped squad grid AND the pinned header's standing line. Uses
//  the same idle/loading/loaded/error State enum as the other screens.
//

import Foundation

@Observable
final class TeamDetailViewModel {
    enum State {
        case idle
        case loading
        case loaded(ClubSquad)
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
            let squad = try await service.fetchRoster(clubID: clubID)
            state = .loaded(squad)
        } catch {
            state = .error(message(for: error))
        }
    }

    /// The loaded squad, or nil until the roster has loaded.
    private var squad: ClubSquad? {
        if case .loaded(let squad) = state { return squad }
        return nil
    }

    /// The squad grouped by position (FWD → MID → DEF → GK); empty unless loaded.
    var positionGroups: [Roster.PositionGroup] {
        squad.map { Roster.grouped($0.athletes) } ?? []
    }

    /// The club's accent color hex for card/badge tinting (nil falls back to the
    /// app accent in Color.teamAccent).
    var accentColorHex: String? { squad?.colorHex }

    /// The header line, e.g. "4th in NWSL — 21 pts"; nil until loaded or when
    /// ESPN didn't provide a standing summary.
    var standingLine: String? { squad?.standingLine }

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
