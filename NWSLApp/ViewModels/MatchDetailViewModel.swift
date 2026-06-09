//
//  MatchDetailViewModel.swift
//  NWSLApp
//
//  Owns the per-match detail screen's async state. The scoreboard `Event` is
//  always in hand (handed in by the Schedule), so the screen can render its
//  header immediately; this view model layers ESPN's richer `/summary` on top —
//  lineups, team stats, the events timeline — fetched on demand for this one
//  match. Uses the same idle/loading/loaded/error State enum as the rest of the
//  app, so a fetch failure degrades to the header alone rather than a blank wall.
//
//  `temporalState` (past/live/future), derived from the scoreboard status, is the
//  spine of the view: it picks the layout (tabbed recap vs. live vs. preview) and
//  whether to poll. The future-match preview is built in `buildPreview` from the
//  shared MatchStore season — see the Live/Future work — so no extra endpoint is
//  needed for it.
//

import Foundation

/// Where this match sits in time — the top-level switch the detail view keys on.
enum MatchTemporalState {
    case past      // status "post" — final recap
    case live      // status "in"  — running, polls for updates
    case future    // status "pre" / unknown — preview
}

@Observable
final class MatchDetailViewModel {
    enum State {
        case idle
        case loading
        case loaded(MatchSummary)
        case error(String)
    }

    /// The scoreboard event — always available, powers the header with no fetch.
    let event: Event
    private(set) var summaryState: State = .idle

    private let service: ESPNService

    init(event: Event, service: ESPNService = ESPNService()) {
        self.event = event
        self.service = service
    }

    /// past / live / future, from the scoreboard status state.
    var temporalState: MatchTemporalState {
        switch event.statusState {
        case "in":   return .live
        case "post": return .past
        default:     return .future   // "pre" or an unknown/absent state
        }
    }

    /// The loaded summary, or nil until it arrives (or if the fetch failed).
    var summary: MatchSummary? {
        if case .loaded(let summary) = summaryState { return summary }
        return nil
    }

    /// Fetches the match summary. Always refetches (so the live 30s poll works);
    /// callers guard on `.idle` for the first load. A failure leaves the screen
    /// on its header-only fallback.
    func loadSummary() async {
        summaryState = .loading
        do {
            summaryState = .loaded(try await service.fetchSummary(eventID: event.id))
        } catch {
            summaryState = .error(message(for: error))
        }
    }

    private func message(for error: Error) -> String {
        switch error {
        case ESPNServiceError.badStatus(let code):
            return "ESPN returned an error (status \(code))."
        case ESPNServiceError.decoding:
            return "Couldn't read the match details."
        case ESPNServiceError.badURL:
            return "Couldn't build the request. This is a bug — please report it."
        default:
            return "Couldn't load match details. Check your connection."
        }
    }
}
