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

    /// Wall-clock time of the last successful load/refresh — the anchor for the in-app
    /// football clock: a live event's `status.clock` (elapsed seconds) was current AS OF
    /// this instant, so the tick shows `clock + (now − lastLoadedAt)`. Updated every ~30s
    /// by the live poll, which re-syncs the clock to reality. nil until the first success.
    private(set) var lastLoadedAt: Date?

    // MARK: Monotonic live-clock tick anchors

    /// Per-live-match anchor for the local football-clock tick. ESPN FREEZES `status.clock` at
    /// 45:00/90:00 through stoppage time, and re-anchoring to `lastLoadedAt` on every ~30s poll
    /// wiped the local accumulation before it could ever cross a minute boundary — pinning the
    /// display at 45'+1'/90'+1' for ALL of stoppage (observed live 2026-07-04). Rule: while a
    /// match's (clock, period) hasn't advanced, KEEP the anchor from when that clock value was
    /// FIRST seen, so `clock + (now − anchor)` keeps counting +2'…+11'. Re-anchor when the clock
    /// advances or the period changes (the halftime pause breaks continuity legitimately).
    struct TickAnchor: Equatable, Codable {
        let clock: Double
        let period: Int
        let date: Date
        /// True when this match was FIRST seen with its clock already frozen at the regulation
        /// cap (45:00/90:00) — i.e. we joined mid-stoppage with no history. The true stoppage
        /// minute is unknowable (ESPN doesn't transmit it), so ticking from "now" would fabricate
        /// 45'+1' at the 7th minute of added time (owner hit this force-closing mid-stoppage,
        /// 2026-07-05). `tickAnchor(for:)` returns nil for these → views fall back to ESPN's own
        /// display string (honest) until the clock advances again and a real anchor forms.
        var freshAtCap: Bool = false
    }

    private var tickAnchors: [String: TickAnchor] = [:] {
        didSet { Self.persistTickAnchors(tickAnchors) }
    }

    /// Anchors survive relaunch (UserDefaults): force-closing mid-stoppage used to reset the
    /// count to 45'+1' because the in-memory history vanished.
    private static let tickAnchorsKey = "matchStore.tickAnchors.v1"
    nonisolated private static func persistTickAnchors(_ anchors: [String: TickAnchor]) {
        if let data = try? JSONEncoder().encode(anchors) {
            UserDefaults.standard.set(data, forKey: tickAnchorsKey)
        }
    }
    nonisolated private static func loadTickAnchors() -> [String: TickAnchor] {
        guard let data = UserDefaults.standard.data(forKey: tickAnchorsKey),
              let anchors = try? JSONDecoder().decode([String: TickAnchor].self, from: data) else { return [:] }
        return anchors
    }

    /// The anchor to feed `LiveMinuteText` for this event. nil for a fresh-at-cap match (see
    /// TickAnchor.freshAtCap — views then show ESPN's display string instead of a fabricated
    /// count) and falls back to `lastLoadedAt` only for a match not in the loaded set.
    func tickAnchor(for eventID: String) -> Date? {
        if let anchor = tickAnchors[eventID] {
            return anchor.freshAtCap ? nil : anchor.date
        }
        return lastLoadedAt
    }

    /// Pure reconcile — nonisolated static so `MatchClockTests` exercises the frozen-clock rule directly.
    nonisolated static func reconciledTickAnchors(
        previous: [String: TickAnchor],
        events: [Event],
        at instant: Date
    ) -> [String: TickAnchor] {
        var next: [String: TickAnchor] = [:]
        for event in events where event.statusState == "in" {
            guard let clock = event.status?.clock else { continue }
            let period = event.status?.period ?? 0
            if let old = previous[event.id], old.period == period, clock <= old.clock {
                next[event.id] = old // frozen/stalled server clock → keep accumulating locally
            } else {
                // First sighting AT the frozen regulation cap (e.g. cold start mid-stoppage):
                // the true stoppage minute is unknowable — flag it so views fall back to ESPN's
                // string instead of fabricating 45'+1'. Clears itself once the clock advances.
                let cap = MatchClock.regulationCap(period: period).map { Double($0) * 60 }
                let freshAtCap = previous[event.id] == nil && cap != nil && clock >= cap!
                next[event.id] = TickAnchor(clock: clock, period: period, date: instant, freshAtCap: freshAtCap)
            }
        }
        return next // non-live matches drop out
    }

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
        self.tickAnchors = Self.loadTickAnchors() // stoppage-count history survives relaunch
    }

    // Always refetches (so pull-to-refresh works). "Load once" is the caller's
    // job — screens guard on `.idle` before kicking the first load, mirroring
    // TeamsView, so revisiting a tab doesn't refetch.
    func load() async {
        state = .loading
        await performLoad(silent: false)
    }

    /// Silent live refresh: refetch and swap in fresh events WITHOUT a `.loading`
    /// flash, so a live game's score/clock advances in place while the user is
    /// looking at the Schedule/Home cards or a Match Detail header. A transient
    /// failure KEEPS the last good schedule on screen (emit diag) rather than
    /// blanking to an error — the opposite of `load()`, whose failure is a hard
    /// `.error`. Drives the RootTabView live-poll loop + scenePhase-active refresh.
    func refresh() async {
        // Before the first successful load there's nothing to refresh in place —
        // fall back to a normal load (which shows the spinner).
        guard case .loaded = state else { await load(); return }
        await performLoad(silent: true)
    }

    /// Whether any loaded match is currently in progress — lets the live poll run
    /// fast (~30s) while a game is on and slow otherwise, and gates the detail poll.
    var hasLiveMatch: Bool { events.contains { $0.statusState == "in" } }

    private func performLoad(silent: Bool) async {
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
            let instant = now()
            lastLoadedAt = instant
            let deduped = dedupedByEventID(matches)
            tickAnchors = Self.reconciledTickAnchors(previous: tickAnchors, events: deduped.map(\.event), at: instant)
            state = .loaded(deduped)
        } catch {
            Diagnostics.shared.record(.apiFailure, "schedule \(silent ? "refresh" : "load"): \(error.localizedDescription)")
            // A silent live-refresh blip must NOT blank the whole tab: keep the last
            // good schedule (state stays `.loaded`). A first-load failure IS a hard
            // error (the schedule is genuinely empty), so surface it.
            if !silent {
                partialErrors = [:]
                state = .error(message(for: error))
            }
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

    /// The loaded ScheduledMatch for an event id — push-tap deep-link resolution.
    func scheduledMatch(for eventID: String) -> ScheduledMatch? {
        if case .loaded(let matches) = state { return matches.first { $0.event.id == eventID } }
        return nil
    }

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
