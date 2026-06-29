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

    /// Per-competition load failures (keyed by house-style label), so the Schedule's
    /// "My teams" can show an honest per-source retry while NWSL keeps working. NWSL
    /// itself never lands here — a NWSL failure is a hard `state = .error`.
    private(set) var partialErrors: [String: String] = [:]

    /// The follow lens, handed in by RootTabView. `load()` reads the followed
    /// national teams (+ later the Champions Cup toggle) so every caller fetches the
    /// same merged NWSL + competition set — no first-loader-wins. nil = NWSL only.
    var following: FollowingStore?

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
        let followedCodes = following?.followedNationalTeams ?? []
        do {
            // NWSL is the spine — its failure is a hard error (the schedule is broken).
            let board = try await service.fetchScoreboard(year: year)
            var matches = board.events.map { ScheduledMatch(event: $0, competition: .nwsl) }

            // Followed women's national teams — each feed is an EXTRA: a failure
            // records a partial error, never breaks the NWSL spine (online-only,
            // no stale fallback). (Champions Cup curated source: a later phase.)
            var errors: [String: String] = [:]
            if !followedCodes.isEmpty {
                let (ntMatches, ntErrors) = await fetchNationalTeamMatches(year: year,
                                                                          followedCodes: followedCodes)
                matches += ntMatches
                errors = ntErrors
            }

            // CONCACAF W Champions Cup (a CLUB competition ESPN does carry) — fetched
            // only when the user's global toggle is on. We keep every match involving
            // an NWSL club here; the My-teams filter narrows to FOLLOWED clubs. Same
            // soft-fail policy as the national-team feeds (never breaks the spine).
            if following?.isConcacafFollowed == true {
                let (ccMatches, ccError) = await fetchChampionsCupMatches(year: year)
                matches += ccMatches
                if let ccError { errors[ChampionsCupFeed.label] = ccError }
            }

            // NWSL Challenge Cup (a single annual NWSL-club match, ESPN slug `usa.nwsl.cup`).
            // UNLIKE the Champions Cup, there is NO opt-in toggle — it's AUTO: fetch it whenever
            // the user follows any club, and the My-teams filter narrows it to fans of the two
            // participating clubs. Same soft-fail policy (never breaks the NWSL spine).
            if !(following?.followedIDs.isEmpty ?? true) {
                let (chMatches, chError) = await fetchChallengeCupMatches(year: year)
                matches += chMatches
                if let chError { errors[ChallengeCupFeed.label] = chError }
            }

            partialErrors = errors
            state = .loaded(dedupedByEventID(matches))
        } catch {
            Diagnostics.shared.record(.apiFailure, "schedule load: \(error.localizedDescription)")
            partialErrors = [:]
            state = .error(message(for: error))
        }
    }

    /// Fetch every national-team feed in parallel, keeping only events that involve a
    /// FOLLOWED national team (matched by FIFA code = ESPN's competitor abbreviation),
    /// tagged with the feed's house-style label. Returns the matches + per-feed errors.
    private func fetchNationalTeamMatches(
        year: Int, followedCodes: Set<String>
    ) async -> (matches: [ScheduledMatch], errors: [String: String]) {
        await withTaskGroup(of: (label: String, result: Result<[ScheduledMatch], Error>).self) { group in
            for feed in NationalTeamFeed.all {
                group.addTask {
                    do {
                        let board = try await self.service.fetchScoreboard(year: year, league: feed.slug)
                        let kept = board.events.filter { event in
                            let home = event.homeCompetitor?.team?.abbreviation
                            let away = event.awayCompetitor?.team?.abbreviation
                            return (home.map(followedCodes.contains) ?? false)
                                || (away.map(followedCodes.contains) ?? false)
                        }.map { ScheduledMatch(event: $0, competition: .international(feed.label)) }
                        return (feed.label, .success(kept))
                    } catch {
                        return (feed.label, .failure(error))
                    }
                }
            }
            var all: [ScheduledMatch] = []
            var errors: [String: String] = [:]
            for await item in group {
                switch item.result {
                case .success(let m): all += m
                case .failure(let error):
                    errors[item.label] = "Couldn't load \(item.label) — pull to retry."
                    // One feed dropping while others load is degraded-but-looks-fine —
                    // exactly the silent partial-failure class. Flag each dropped feed.
                    Diagnostics.shared.record(.apiFailure, "schedule feed \(item.label): \(error.localizedDescription)")
                }
            }
            return (all, errors)
        }
    }

    /// Fetch the CONCACAF W Champions Cup feed, keeping only matches that involve an
    /// NWSL club (a known abbreviation — DesignTeamColors covers the 16; the Liga MX
    /// vs Liga MX ties aren't "yours"). Tagged `.concacafChampionsCup`. Soft-fail.
    private func fetchChampionsCupMatches(year: Int) async -> (matches: [ScheduledMatch], error: String?) {
        do {
            let board = try await service.fetchScoreboard(year: year, league: ChampionsCupFeed.slug)
            let kept = board.events.filter { event in
                DesignTeamColors.hex(for: event.homeCompetitor?.team?.abbreviation) != nil
                    || DesignTeamColors.hex(for: event.awayCompetitor?.team?.abbreviation) != nil
            }.map { ScheduledMatch(event: $0, competition: .concacafChampionsCup) }
            return (kept, nil)
        } catch {
            Diagnostics.shared.record(.apiFailure, "schedule \(ChampionsCupFeed.label): \(error.localizedDescription)")
            return ([], "Couldn't load \(ChampionsCupFeed.label) — pull to retry.")
        }
    }

    /// Fetch the NWSL Challenge Cup feed (a single annual NWSL-club-vs-NWSL-club match). The
    /// feed is already just that one match, but we keep the same NWSL-club guard as the Champions
    /// Cup so a stray non-NWSL entry can never slip in. Tagged `.challengeCup` (`isNWSL == false`,
    /// so it stays out of league records/standings/Predict). Soft-fail — never breaks the spine.
    private func fetchChallengeCupMatches(year: Int) async -> (matches: [ScheduledMatch], error: String?) {
        do {
            let board = try await service.fetchScoreboard(year: year, league: ChallengeCupFeed.slug)
            let kept = board.events.filter { event in
                DesignTeamColors.hex(for: event.homeCompetitor?.team?.abbreviation) != nil
                    || DesignTeamColors.hex(for: event.awayCompetitor?.team?.abbreviation) != nil
            }.map { ScheduledMatch(event: $0, competition: .challengeCup) }
            return (kept, nil)
        } catch {
            Diagnostics.shared.record(.apiFailure, "schedule \(ChallengeCupFeed.label): \(error.localizedDescription)")
            return ([], "Couldn't load \(ChallengeCupFeed.label) — pull to retry.")
        }
    }

    /// Drop cross-feed duplicates (the same match surfacing in two national-team
    /// feeds), keeping the first tag. NWSL + national-team event ids never collide.
    private func dedupedByEventID(_ matches: [ScheduledMatch]) -> [ScheduledMatch] {
        var seen = Set<String>()
        return matches.filter { seen.insert($0.id).inserted }
    }

    /// The loaded season as tagged matches (empty unless we're in `.loaded`).
    var matches: [ScheduledMatch] {
        if case .loaded(let matches) = state { return matches }
        return []
    }

    /// The loaded season as raw events — the shape existing readers (Schedule, Home,
    /// Predict) already use. Derived from `matches`, ALL competitions.
    var events: [Event] { matches.map(\.event) }

    /// NWSL-only events. Use this (not `events`) for anything that joins by NWSL club
    /// abbreviation — Standings' Last-5, season-form comparisons, `matches(for:)` —
    /// so a Champions Cup match (which carries a real NWSL abbreviation like WAS/GFC)
    /// never leaks into a club's league record. National-team matches never collide
    /// (their codes aren't NWSL abbreviations), but the Champions Cup ones would.
    var nwslEvents: [Event] { matches.filter { $0.competition.isNWSL }.map(\.event) }

    // TEMP (fragile join): we match a club to its matches by `abbreviation`
    // because ESPN's scoreboard competitor `Team` carries no id (only the
    // `/teams` Club does). Verified in-sim that all 16 clubs' abbreviations are
    // identical across both endpoints, so this works today — but an abbreviation
    // rename (relocation/rebrand) would silently empty a club's schedule. Real
    // fix when we have a back end: a normalized club-id map, or a proxy that
    // attaches a stable id to every competitor. Until then the Team page shows a
    // visible empty state rather than failing silently.
    func matches(for club: Club) -> [Event] {
        // NWSL-only: a club's league record/fixtures, not its Champions Cup ties
        // (those reach the schedule via the tagged `matches`/My-teams path instead).
        let clubMatches = nwslEvents.filter { event in
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
