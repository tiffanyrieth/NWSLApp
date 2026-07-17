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
import MatchClockKit

/// The live-clock anchor engine reads matches through this minimal surface, so MatchClockKit stays a
/// leaf and never imports the ESPN `Event` model. `id` + `statusState` already satisfy the protocol.
extension Event: ClockTickSource {
    var clockSeconds: Double? { status?.clock }
    var period: Int? { status?.period }
}

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

    /// Per-live-match anchor for the local football-clock tick (the stoppage-time freeze fix). The
    /// `TickAnchor` value + the reconcile rule live in `MatchClockKit` now; MatchStore owns only the
    /// live-state set + its durability (persist below), and delegates the invariant logic to the
    /// package. See `MatchClockKit.TickAnchor` for the frozen-clock rule.
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
        await performWindowedRefresh()
    }

    /// Yesterday→tomorrow as ESPN's `dates=YYYYMMDD-YYYYMMDD` (UTC; ±1 day covers any ET/UTC
    /// date-boundary game) — the small, always-fresh window the live poll fetches instead of the
    /// ~2MB season. Mirrors the watcher's `scoreboardWindow()`.
    static func scoreboardWindow(now: Date = Date()) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .gmt
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = .gmt
        fmt.dateFormat = "yyyyMMdd"
        func day(_ offset: Int) -> String {
            let d = cal.date(byAdding: .day, value: offset, to: now) ?? now
            return fmt.string(from: d)
        }
        return "\(day(-1))-\(day(1))"
    }

    /// Silent live refresh over the small window (not the ~2MB season). Fetches the windowed NWSL
    /// board (+ the same followed NT / Champions / Challenge feeds, windowed) and MERGES the fresh
    /// events over the loaded season by event id — so a live match's score/clock advances in place
    /// without re-downloading the whole season, and live state rides the fresh windowed query rather
    /// than ESPN's laggy full-season cache. A transient failure KEEPS the last good schedule (never
    /// blanks). Falls back to a full `load()` before the first successful load.
    private func performWindowedRefresh() async {
        guard case .loaded(let existing) = state else { await load(); return }
        let dates = Self.scoreboardWindow(now: now())
        let year = calendar.component(.year, from: now())
        let followedCodes = following?.followedNationalTeams ?? []
        // AUX-FEED GATE (2026-07-16 polling fix, the app-side fixture window): the live tick
        // re-fetches an auxiliary feed ONLY when the loaded season shows one of ITS fixtures near
        // now — the Challenge Cup is one match a YEAR, yet it was fetched every 30s tick all
        // season. The NWSL board stays unconditional (the spine: live-flip detection + freshness).
        let aux = Self.auxFeedsWorthPolling(loaded: existing, now: now())
        do {
            var fresh = try await service.fetchScoreboard(dates: dates).events
                .map { ScheduledMatch(event: $0, competition: .nwsl) }
            if !followedCodes.isEmpty, aux.nt {
                let (nt, _) = await fetchNationalTeamMatches(year: year, followedCodes: followedCodes, dates: dates)
                fresh += nt
            }
            if following?.isConcacafFollowed == true, aux.championsCup {
                let (cc, _) = await fetchChampionsCupMatches(year: year, dates: dates)
                fresh += cc
            }
            if !(following?.followedIDs.isEmpty ?? true), aux.challengeCup {
                let (ch, _) = await fetchChallengeCupMatches(year: year, dates: dates)
                fresh += ch
            }
            // Replace any loaded event that reappears in the window with its fresh copy; keep the rest
            // of the season; append a window-only event not already loaded (rare mid-session addition).
            let freshById = Dictionary(fresh.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let existingIds = Set(existing.map(\.id))
            let merged = existing.map { freshById[$0.id] ?? $0 } + fresh.filter { !existingIds.contains($0.id) }
            let deduped = dedupedByEventID(merged)
            let instant = now()
            lastLoadedAt = instant
            tickAnchors = TickAnchor.reconcile(previous: tickAnchors, sources: deduped.map(\.event), at: instant)
            state = .loaded(deduped)
        } catch {
            // A live-poll blip must NOT blank the tab — keep the last good schedule (state stays `.loaded`).
            Diagnostics.shared.record(.apiFailure, "schedule windowed refresh: \(error.localizedDescription)")
        }
    }

    /// Whether any loaded match is currently in progress — lets the live poll run
    /// fast (~60s) while a game is on and slow otherwise, and gates the detail poll.
    var hasLiveMatch: Bool { events.contains { $0.statusState == "in" } }

    /// How far around "now" an auxiliary competition's fixture must sit for the live tick to keep
    /// re-fetching its feed. ±36h comfortably covers the fetch window (`scoreboardWindow` =
    /// UTC yesterday→tomorrow) so a gated feed can never miss a fixture the fetch would have seen.
    private static let auxFeedWindow: TimeInterval = 36 * 3600
    /// Which AUXILIARY feeds are worth re-fetching on a windowed (live) refresh: each counts only
    /// if the LOADED season carries one of its fixtures with a kickoff within ±36h of now — or a
    /// fixture with an unparseable kickoff (fail OPEN: a date we can't read must not silently
    /// starve its feed). Pure + unit-tested (MatchStoreAuxGateTests). The full-season `load()` is
    /// deliberately ungated — it's how aux fixtures are discovered in the first place; the rare
    /// mid-session brand-new aux fixture waits for the next full load (launch/foreground/follow
    /// change), the same accepted class as the watcher's discovery gap.
    nonisolated static func auxFeedsWorthPolling(
        loaded: [ScheduledMatch], now: Date
    ) -> (nt: Bool, championsCup: Bool, challengeCup: Bool) {
        var nt = false, championsCup = false, challengeCup = false
        for match in loaded {
            // Fail open on a missing/unparseable date; otherwise require kickoff near now.
            let near = match.event.kickoff.map { abs($0.timeIntervalSince(now)) <= auxFeedWindow } ?? true
            guard near else { continue }
            switch match.competition {
            case .international: nt = true
            case .concacafChampionsCup: championsCup = true
            case .challengeCup: challengeCup = true
            case .nwsl: break   // the NWSL board is always fetched — no gate to feed
            }
            if nt && championsCup && challengeCup { break }
        }
        return (nt, championsCup, challengeCup)
    }

    /// A new calendar year's feed must carry at least this many NWSL fixtures before the app
    /// rolls over to it — guards the Dec→fixtures-release gap (a stray placeholder event must not
    /// wipe the completed season; owner rule: last season stays browsable until the new schedule
    /// is actually published).
    private static let seasonRolloverMinimumFixtures = 10

    private func performLoad(silent: Bool) async {
        var year = calendar.component(.year, from: now())
        let followedCodes = following?.followedNationalTeams ?? []
        do {
            // NWSL is the spine — its failure is a hard error (the schedule is broken).
            var board = try await service.fetchScoreboard(year: year)
            // SEASON ROLLOVER: if the new calendar year has no published schedule yet, keep
            // serving the PRIOR season in full (results + playoffs + final) — no empty-app
            // window between the championship and the next fixture release.
            if board.events.count < Self.seasonRolloverMinimumFixtures {
                let priorBoard = try await service.fetchScoreboard(year: year - 1)
                if priorBoard.events.count >= Self.seasonRolloverMinimumFixtures {
                    Diagnostics.shared.record(.staleServe,
                        "season rollover gap: \(year) has \(board.events.count) fixtures — serving \(year - 1)")
                    board = priorBoard
                    year -= 1   // the extra feeds below follow the season we're serving
                }
            }
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
            tickAnchors = TickAnchor.reconcile(previous: tickAnchors, sources: deduped.map(\.event), at: instant)
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

    /// Fetch the RELEVANT national-team feeds in parallel — the globals + each followed
    /// country's confederation feeds (`NationalTeamFeed.scopedFeeds`, the 2026-07-16 polling
    /// fix: following ZAM polls ~7 feeds, not all 15 — a country can't appear in another
    /// confederation's championship). Keeps only events that involve a FOLLOWED national team
    /// (matched by FIFA code = ESPN's competitor abbreviation), tagged with the feed's
    /// house-style label. Returns the matches + per-feed errors. An unmapped code fails OPEN
    /// (all feeds, so no fixture is ever silently missed) + a Diagnostics breadcrumb.
    private func fetchNationalTeamMatches(
        year: Int, followedCodes: Set<String>, dates: String? = nil
    ) async -> (matches: [ScheduledMatch], errors: [String: String]) {
        let scoped = NationalTeamFeed.scopedFeeds(forFollowedCodes: followedCodes)
        for code in scoped.unmapped {
            Diagnostics.shared.record(.unexpectedEmpty, "NT confederation map miss: \(code) — polling all feeds (fail-open)")
        }
        return await withTaskGroup(of: (label: String, result: Result<[ScheduledMatch], Error>).self) { group in
            for feed in scoped.feeds {
                group.addTask {
                    do {
                        let board = try await self.service.fetchScoreboard(year: year, league: feed.slug, dates: dates)
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
    private func fetchChampionsCupMatches(year: Int, dates: String? = nil) async -> (matches: [ScheduledMatch], error: String?) {
        do {
            let board = try await service.fetchScoreboard(year: year, league: ChampionsCupFeed.slug, dates: dates)
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
    private func fetchChallengeCupMatches(year: Int, dates: String? = nil) async -> (matches: [ScheduledMatch], error: String?) {
        do {
            let board = try await service.fetchScoreboard(year: year, league: ChallengeCupFeed.slug, dates: dates)
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
