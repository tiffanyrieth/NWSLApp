//
//  ClubStore.swift
//  NWSLApp
//
//  The league's club directory (all 16 NWSL clubs), fetched once and shared
//  app-wide. Like MatchStore, this lives in Stores/ (not ViewModels/) and is
//  injected via `.environment`, because many screens need the same directory:
//  Teams lists it, Onboarding picks from it, and Home/Schedule/Feed resolve the
//  user's followed IDs → Clubs (crests, names, abbreviations). One fetch, many
//  readers — rather than each screen re-downloading the same 16 clubs. This
//  consolidates the per-view-model `fetchTeams()` calls called out in CLAUDE.md
//  What's-Next #15, and gives the My-teams schedule filter a real error/retry
//  path (#16) instead of a silently-swallowed failure.
//
//  `club(forAbbreviation:)` is the lookup the My-teams filter and Home's content
//  modules need (scoreboard competitors carry an abbreviation, not a club id).
//  ClubStore doesn't *fix* that fragile join — a real fix needs a stable id on
//  ESPN's competitors (see MatchStore.matches(for:), #9) — it just gives the
//  lookup one home.
//
//  Like MatchStore, this is also the seam a future caching proxy/back end slots
//  behind: today it calls ESPN's /teams directly; later it can read a normalized
//  directory from the server.
//

import Foundation

@Observable
final class ClubStore {
    // Same idle/loading/loaded/error shape the rest of the app uses, so every
    // async fetch models its outcomes identically.
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

    // Always refetches (so pull-to-refresh works). "Load once" is the caller's
    // job — screens guard on `.idle` before kicking the first load, mirroring
    // MatchStore — so revisiting a tab doesn't refetch.
    func load() async {
        state = .loading
        do {
            state = .loaded(try await service.fetchTeams())
        } catch {
            state = .error(message(for: error))
        }
    }

    /// Tracks an in-flight `loadIfNeeded` so concurrent callers await the SAME load.
    private var loadTask: Task<Void, Never>?

    /// Ensure the directory is loaded, deduping concurrent callers: returns immediately if already
    /// loaded, awaits an in-flight load if one is running, otherwise starts one.
    ///
    /// This is what content-SCOPING callers (Home `loadContent`, Feed) MUST use instead of the
    /// `if case .idle { await load() }` guard: they resolve followed IDs → abbreviations from
    /// `clubs`, so they must not proceed until clubs are actually `.loaded`. Proceeding while a
    /// (e.g. prewarmed) load is still `.loading` yields an EMPTY scope → an unscoped `/team-videos`
    /// request → an empty Home feed. (`load()` stays for forced pull-to-refresh.)
    func loadIfNeeded() async {
        if case .loaded = state { return }
        if let loadTask { await loadTask.value; return }
        let task = Task { await self.load() }
        loadTask = task
        await task.value
        loadTask = nil
    }

    /// The loaded directory (empty unless we're in `.loaded`).
    var clubs: [Club] {
        if case .loaded(let clubs) = state { return clubs }
        return []
    }

    /// A club by its stable ESPN team id (the key FollowingStore stores).
    func club(id: String) -> Club? {
        clubs.first { $0.id == id }
    }

    /// A club by its team abbreviation — the join key scoreboard competitors and
    /// the content seeds carry (see MatchStore.matches(for:)).
    func club(forAbbreviation abbreviation: String) -> Club? {
        clubs.first { $0.abbreviation == abbreviation }
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
