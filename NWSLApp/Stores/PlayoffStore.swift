//
//  PlayoffStore.swift
//  NWSLApp
//
//  The postseason state, DERIVED (never stored as separate truth) from the season schedule.
//  Injected once via `.environment`, read by the SCHEDULE tab (round sections + the Playoffs
//  chip). It does NOT run its own live poll — it re-derives whenever ScheduleView hands it
//  fresh MatchStore events (one-fetch-many-readers).
//
//  Three phases, all data-driven:
//   • PRE-SEEDING (year-round): `windows` (ESPN's published season-type calendar) drives the
//     schedule's TBD playoff tail; the CLINCH table (computed purely from the season's own
//     results — no extra fetch) gates the Playoffs chip (visible at 2+ mathematical clinches).
//   • SEEDED: real `playoffs---*` events with placed teams exist → derive the bracket (seeds
//     from a one-shot standings fetch — ESPN's ranks carry the official tiebreakers).
//   • OFFSEASON: MatchStore's season rollover keeps serving the completed season (incl. the
//     playoffs) until the new season's fixtures publish, so this store just keeps deriving —
//     no special historical path needed.
//

import Foundation

@MainActor
@Observable
final class PlayoffStore {
    private(set) var bracket: PlayoffBracket?
    /// Real playoff fixtures with placed teams exist (seeding locked).
    private(set) var isPostseasonActive = false
    /// The events the current bracket was derived from (real or, in DEBUG, simulated) — the
    /// source for resolving a tapped matchup's `eventID` back to an `Event` for MatchDetailView.
    private(set) var sourceEvents: [Event] = []
    /// ESPN's published season-phase calendar (playoff-round date windows) — the TBD tail.
    private(set) var windows: [SeasonWindow] = []
    /// The clinch table computed from the loaded season's results (regular season only).
    private(set) var clinchTable: [PlayoffClinch.TeamLine] = []

    private let service: ESPNService
    private var simulating = false
    private var windowsLoadedForYear: Int?
    /// Standings seeds cached per season year (final once the postseason starts).
    private var seedsCache: [Int: [String: Int]] = [:]

    init(service: ESPNService = ESPNService()) {
        self.service = service
    }

    // MARK: Chip + clinch signals

    var clinchedAbbreviations: Set<String> { PlayoffClinch.clinched(in: clinchTable) }

    /// The Playoffs chip appears at 2+ mathematical clinches (owner rule) or once seeded.
    var isChipVisible: Bool { isPostseasonActive || clinchedAbbreviations.count >= 2 }

    /// One team's "my path to the playoffs" status (clinch window).
    func clinchStatus(of abbreviation: String) -> PlayoffClinch.Status? {
        PlayoffClinch.status(of: abbreviation, table: clinchTable)
    }

    // MARK: Upcoming rounds (the pre-seeding TBD tail)

    struct UpcomingRound: Identifiable {
        let round: PlayoffRound
        let start: Date?
        let end: Date?
        let slotCount: Int
        var id: String { round.slug }
    }

    /// The playoff rounds ahead, from ESPN's published windows — shown as TBD sections at the
    /// schedule's end before seeding. Standard slot counts from the 8-team tree; an unknown
    /// future slug still shows (1 generic slot) + trips the format diag.
    var upcomingRounds: [UpcomingRound] {
        let tree = SeedTree(teamCount: 8)
        let counts: [String: Int] = [
            PlayoffRound.quarterfinal.slug: tree.matchupsPerRound[0],
            PlayoffRound.semifinal.slug: tree.matchupsPerRound[1],
            PlayoffRound.championship.slug: tree.matchupsPerRound[2],
        ]
        return windows.compactMap { window in
            guard window.isPlayoff, let round = window.round else { return nil }
            if round.isUnknown {
                Diagnostics.shared.record(.playoffFormatMismatch, "unknown season window slug '\(round.slug)'")
            }
            return UpcomingRound(round: round, start: window.start, end: window.end,
                                 slotCount: counts[round.slug] ?? 1)
        }.sorted { $0.round < $1.round }
    }

    // MARK: Sync (called by ScheduleView when MatchStore updates)

    /// Re-derive all postseason state from the loaded season. `nwslEvents` = MatchStore's
    /// NWSL-competition events (regular season + playoffs; the rollover means these may be the
    /// PRIOR season during the offseason gap — everything here follows the events' own year).
    func sync(nwslEvents: [Event], now: Date = Date()) async {
        if simulating { return }   // DEBUG simulate override owns the state

        await loadWindowsIfNeeded(now: now)

        // Clinch table: computed purely from the season's own results — no fetch.
        clinchTable = PlayoffClinch.table(fromRegularSeason: nwslEvents)

        let placedPlayoffs = nwslEvents.filter { $0.isPlayoffEvent && $0.hasTwoPlacedTeams }
        guard !placedPlayoffs.isEmpty else {
            isPostseasonActive = false
            bracket = nil
            sourceEvents = []
            return
        }

        // Seeded: seeds from the season's FINAL standings (official tiebreakers), cached per year.
        let seasonYear = placedPlayoffs.first?.season?.year
            ?? Calendar.current.component(.year, from: now)
        let seeds = await seeds(forSeason: seasonYear)
        let override = await service.fetchPlayoffOverride(season: seasonYear)
        apply(events: nwslEvents, seeds: seeds, now: now, override: override)
    }

    private func seeds(forSeason year: Int) async -> [String: Int] {
        if let cached = seedsCache[year] { return cached }
        do {
            let currentYear = Calendar.current.component(.year, from: Date())
            let rows = try await service.fetchStandings(season: year == currentYear ? nil : year)
            var seeds: [String: Int] = [:]
            for row in rows { seeds[row.club.abbreviation] = row.rank }
            seedsCache[year] = seeds
            return seeds
        } catch {
            Diagnostics.shared.record(.apiFailure, "playoff seeds \(year): \(error.localizedDescription)")
            return [:]
        }
    }

    private func loadWindowsIfNeeded(now: Date) async {
        let year = Calendar.current.component(.year, from: now)
        guard windowsLoadedForYear != year else { return }
        windowsLoadedForYear = year
        windows = await service.fetchSeasonWindows(year: year)
    }

    private func apply(events: [Event], seeds: [String: Int], now: Date, override: PlayoffOverride?) {
        // Kill switch: operator hid the feature (ESPN too broken to show anything honest).
        if override?.hideBracket == true {
            Diagnostics.shared.record(.playoffFormatMismatch, "override: hideBracket")
            isPostseasonActive = false; bracket = nil; sourceEvents = []
            return
        }
        // Layer operator corrections onto the raw inputs BEFORE derive, so a fixed winner
        // propagates to later rounds.
        let corrected = override?.corrected(events: events, seeds: seeds) ?? (events: events, seeds: seeds)
        sourceEvents = corrected.events
        let derived = PlayoffBracket.derive(from: corrected.events, seeds: corrected.seeds, now: now,
                                            forcedTeamCount: override?.teamCount)
        bracket = derived
        isPostseasonActive = corrected.events.contains { $0.isPlayoffEvent && $0.hasTwoPlacedTeams }
        if let reason = derived.tripwireReason {
            // Fail LOUD to the engineer: the published bracket diverged from the seed tree.
            Diagnostics.shared.record(.playoffFormatMismatch, reason)
        }
    }

    // MARK: Reads for the views

    /// Resolve a matchup's `eventID` to the underlying Event (for MatchDetailView navigation).
    func event(forID id: String) -> Event? { sourceEvents.first { $0.id == id } }

    // MARK: DEBUG simulate harness

    #if DEBUG
    /// Drive the whole feature off REAL 2025 postseason data (in-code, no network) so every
    /// state renders in the sim months before the live playoffs. See PostseasonSimulator.
    func simulatePostseason2025(stage: PostseasonSimulator.Stage = .midRun) {
        simulating = true
        windows = PostseasonSimulator.windows2025
        switch stage {
        case .preSeeding:
            clinchTable = []
            isPostseasonActive = false; bracket = nil; sourceEvents = []
        case .clinchWindow:
            clinchTable = PostseasonSimulator.clinchTable
            isPostseasonActive = false; bracket = nil; sourceEvents = []
        default:
            let (events, seeds, now) = PostseasonSimulator.snapshot(stage)
            clinchTable = PostseasonSimulator.clinchTable
            sourceEvents = events
            let derived = PlayoffBracket.derive(from: events, seeds: seeds, now: now)
            bracket = derived
            isPostseasonActive = true
            if let reason = derived.tripwireReason {
                Diagnostics.shared.record(.playoffFormatMismatch, reason)
            }
        }
    }
    #endif
}

private extension Event {
    /// Both competitors carry a real team abbreviation (a placed, non-TBD playoff game).
    var hasTwoPlacedTeams: Bool {
        homeCompetitor?.team?.abbreviation != nil && awayCompetitor?.team?.abbreviation != nil
    }
}
