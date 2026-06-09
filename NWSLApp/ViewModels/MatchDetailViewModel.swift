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

/// One result in a team's recent form.
enum MatchResult { case win, draw, loss }

/// A team's season-to-date form, derived from the shared season for the
/// future-match preview (see MatchDetailViewModel.buildPreview).
struct TeamSeasonForm {
    let played: Int
    let goalsFor: Int
    let goalsAgainst: Int
    let points: Int
    /// Up to the last 5 results, oldest → newest.
    let recent: [MatchResult]

    static let empty = TeamSeasonForm(played: 0, goalsFor: 0, goalsAgainst: 0, points: 0, recent: [])

    var goalsPerMatch: Double { played > 0 ? Double(goalsFor) / Double(played) : 0 }
    var concededPerMatch: Double { played > 0 ? Double(goalsAgainst) / Double(played) : 0 }
    var pointsPerGame: Double { played > 0 ? Double(points) / Double(played) : 0 }
}

/// Both sides' form for the future-match preview.
struct MatchPreview {
    let home: TeamSeasonForm
    let away: TeamSeasonForm

    /// Any completed games on either side — else there's nothing to compare.
    var hasData: Bool { home.played > 0 || away.played > 0 }
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

    /// Silent refresh for the live poll: swaps in fresh data on success but
    /// leaves the current content (no `.loading` flash) and ignores transient
    /// poll failures — the screen keeps showing the last good summary.
    func refresh() async {
        if let fresh = try? await service.fetchSummary(eventID: event.id) {
            summaryState = .loaded(fresh)
        }
    }

    // MARK: - Future-match preview
    //
    // Pure derivation from the shared season (MatchStore) — no extra endpoint.
    // The summary endpoint is empty before kickoff, so the preview's numbers come
    // from each team's completed results. Possession/shots/SOT/pass-accuracy
    // season averages aren't derivable without per-match aggregation, so they're
    // intentionally omitted (see CLAUDE.md What's-Next) rather than faked.

    func buildPreview(season: [Event]) -> MatchPreview {
        MatchPreview(
            home: form(for: event.homeCompetitor?.team?.abbreviation, in: season),
            away: form(for: event.awayCompetitor?.team?.abbreviation, in: season)
        )
    }

    /// A team's season-to-date form from completed events it played in (this
    /// match excluded), oldest → newest. Joins on abbreviation, the same key
    /// MatchStore.matches(for:) uses.
    private func form(for abbr: String?, in season: [Event]) -> TeamSeasonForm {
        guard let abbr else { return .empty }
        let games = season
            .filter { $0.statusState == "post" && $0.id != event.id && involves(abbr, $0) }
            .sorted { ($0.kickoff ?? .distantPast) < ($1.kickoff ?? .distantPast) }

        var goalsFor = 0, goalsAgainst = 0, points = 0
        var results: [MatchResult] = []
        for game in games {
            guard let (scored, conceded) = scoreLine(abbr, game) else { continue }
            goalsFor += scored
            goalsAgainst += conceded
            let result: MatchResult = scored > conceded ? .win : (scored == conceded ? .draw : .loss)
            results.append(result)
            points += result == .win ? 3 : (result == .draw ? 1 : 0)
        }
        return TeamSeasonForm(
            played: results.count,
            goalsFor: goalsFor,
            goalsAgainst: goalsAgainst,
            points: points,
            recent: Array(results.suffix(5))
        )
    }

    private func involves(_ abbr: String, _ event: Event) -> Bool {
        event.homeCompetitor?.team?.abbreviation == abbr
            || event.awayCompetitor?.team?.abbreviation == abbr
    }

    /// (goals scored, goals conceded) for `abbr` in `event`, or nil if either
    /// score is missing/non-numeric.
    private func scoreLine(_ abbr: String, _ event: Event) -> (Int, Int)? {
        let isHome = event.homeCompetitor?.team?.abbreviation == abbr
        let mine = isHome ? event.homeCompetitor : event.awayCompetitor
        let other = isHome ? event.awayCompetitor : event.homeCompetitor
        guard let scored = mine?.score.flatMap(Int.init),
              let conceded = other?.score.flatMap(Int.init) else { return nil }
        return (scored, conceded)
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
