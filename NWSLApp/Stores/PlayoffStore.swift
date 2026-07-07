//
//  PlayoffStore.swift
//  NWSLApp
//
//  The postseason bracket, DERIVED (never stored as separate truth) from the season
//  schedule + standings. Injected once via `.environment`, read by StandingsView's three
//  playoff segments. It does NOT run its own live poll — it re-derives whenever the
//  Standings tab hands it fresh MatchStore events + standings seeds (one-fetch-many-readers).
//
//  Activation is data-driven: real `playoffs---*` events with two placed teams == the
//  postseason has begun (seeding locked, right after the final regular-season game). The
//  ONLY offseason self-fetch is the historical case below.
//
//  Retention (owner decision): the completed bracket stays viewable through the offseason.
//  During the season the current year's playoff events live in MatchStore, so the common
//  path needs no extra fetch. In the Jan–Feb gap (new calendar year, next season not yet
//  started) the current-year fetch has no playoff games, so we self-fetch the PRIOR year's
//  scoreboard + final standings ONCE to keep the champion on screen until the new season
//  kicks off (at which point MatchStore carries regular-season games again → inactive).
//

import Foundation

@MainActor
@Observable
final class PlayoffStore {
    private(set) var bracket: PlayoffBracket?
    /// The postseason is live/complete for the relevant season → StandingsView shows the picker.
    private(set) var isPostseasonActive = false

    /// The events the current bracket was derived from (real or, in DEBUG, simulated) — the
    /// source for resolving a tapped matchup's `eventID` back to an `Event` for MatchDetailView.
    private(set) var sourceEvents: [Event] = []

    private let service: ESPNService
    private var historicalLoaded = false
    private var simulating = false
    /// Cheap change-detection so we don't re-derive on every identical MatchStore emit.
    private var lastSignature = ""

    init(service: ESPNService = ESPNService()) {
        self.service = service
    }

    // MARK: Sync (called by StandingsView when MatchStore / standings update)

    /// Re-derive from the current season's events + seeds. Falls back to the historical
    /// prior-year bracket during the offseason gap. `seeds` = abbr→rank from the live standings.
    func sync(matchEvents: [Event], seeds: [String: Int], now: Date = Date()) async {
        if simulating { return }   // DEBUG simulate override owns the state

        let currentPlayoffs = matchEvents.filter { $0.isPlayoffEvent && $0.hasTwoPlacedTeams }
        if !currentPlayoffs.isEmpty {
            historicalLoaded = false
            let sig = "cur:" + currentPlayoffs.map { "\($0.id)\($0.statusState ?? "")" }.joined() + seeds.count.description
            guard sig != lastSignature else { return }
            lastSignature = sig
            apply(events: matchEvents, seeds: seeds, now: now)
            return
        }

        // No current-season playoff games. Offseason window → load last year's bracket once.
        if Self.isOffseasonWindow(now) {
            if !historicalLoaded { await loadHistorical(now: now) }
        } else {
            // Regular season (or preseason with games scheduled) → nothing to show.
            historicalLoaded = false
            lastSignature = "inactive"
            isPostseasonActive = false
            bracket = nil
            sourceEvents = []
        }
    }

    private func apply(events: [Event], seeds: [String: Int], now: Date) {
        sourceEvents = events
        let derived = PlayoffBracket.derive(from: events, seeds: seeds, now: now)
        bracket = derived
        isPostseasonActive = events.contains { $0.isPlayoffEvent && $0.hasTwoPlacedTeams }
        if let reason = derived.tripwireReason {
            // Fail LOUD to the engineer: the published bracket diverged from the seed tree.
            Diagnostics.shared.record(.playoffFormatMismatch, reason)
        }
    }

    private func loadHistorical(now: Date) async {
        let priorYear = Calendar.current.component(.year, from: now) - 1
        do {
            let board = try await service.fetchScoreboard(year: priorYear)
            let rows = try await service.fetchStandings(season: priorYear)
            var seeds: [String: Int] = [:]
            for row in rows { seeds[row.club.abbreviation] = row.rank }
            historicalLoaded = true
            guard board.events.contains(where: { $0.isPlayoffEvent }) else {
                isPostseasonActive = false; bracket = nil; sourceEvents = []
                return
            }
            apply(events: board.events, seeds: seeds, now: now)
        } catch {
            Diagnostics.shared.record(.apiFailure, "playoff historical \(priorYear): \(error.localizedDescription)")
            isPostseasonActive = false
        }
    }

    // MARK: Reads for the views

    /// Resolve a matchup's `eventID` to the underlying Event (for MatchDetailView navigation).
    func event(forID id: String) -> Event? { sourceEvents.first { $0.id == id } }

    /// Followed abbreviations that are IN the bracket (used for the default-segment choice +
    /// which Your Path sections to render).
    func followedInBracket(_ followedAbbreviations: [String]) -> [String] {
        guard let bracket else { return [] }
        return followedAbbreviations.filter { bracket.seeds[$0] != nil }
    }

    /// The default segment on a fresh postseason open: Your Path if a followed team is in the
    /// bracket, else Bracket (README rule).
    func defaultSegment(followedAbbreviations: [String]) -> PlayoffSegment {
        followedInBracket(followedAbbreviations).isEmpty ? .bracket : .yourPath
    }

    // MARK: Offseason window

    /// Jan–Feb: the calendar year has rolled but the new NWSL season hasn't started, so the
    /// current-year fetch has no games yet. Keep last season's bracket alive here.
    static func isOffseasonWindow(_ now: Date) -> Bool {
        let month = Calendar.current.component(.month, from: now)
        return month == 1 || month == 2
    }

    // MARK: DEBUG simulate harness

    #if DEBUG
    /// Drive the whole feature off the REAL 2025 playoff data (in-code, no network) so every
    /// state renders in the sim months before the live postseason. See PostseasonSimulator.
    func simulatePostseason2025(stage: PostseasonSimulator.Stage = .midRun) {
        simulating = true
        let (events, seeds, now) = PostseasonSimulator.snapshot(stage)
        sourceEvents = events
        let derived = PlayoffBracket.derive(from: events, seeds: seeds, now: now)
        bracket = derived
        isPostseasonActive = true
        if let reason = derived.tripwireReason {
            Diagnostics.shared.record(.playoffFormatMismatch, reason)
        }
    }
    #endif
}

/// The three Standings-tab postseason segments.
enum PlayoffSegment: String, CaseIterable, Identifiable {
    case yourPath, bracket, standings
    var id: String { rawValue }
    var label: String {
        switch self {
        case .yourPath: return "Your Path"
        case .bracket: return "Bracket"
        case .standings: return "Standings"
        }
    }
}

private extension Event {
    /// Both competitors carry a real team abbreviation (a placed, non-TBD playoff game).
    var hasTwoPlacedTeams: Bool {
        homeCompetitor?.team?.abbreviation != nil && awayCompetitor?.team?.abbreviation != nil
    }
}
