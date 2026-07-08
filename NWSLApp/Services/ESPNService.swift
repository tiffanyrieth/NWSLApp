//
//  ESPNService.swift
//  NWSLApp
//
//  Thin HTTP client around ESPN's unofficial NWSL endpoints.
//  See CLAUDE.md → "Data Source" — this API is not officially supported,
//  so we decode defensively (see Scoreboard.swift) and surface typed errors.
//

import Foundation

enum ESPNServiceError: Error {
    case badStatus(Int)
    case decoding(Error)
    case badURL
}

struct ESPNService {
    var session: URLSession = .shared
    // Force-unwrap is safe: the string is a compile-time constant valid URL.
    // If a future edit makes it invalid, this crashes on first launch in dev — the right time to catch it.
    private let base = URL(string: "https://site.api.espn.com/apis/site/v2/sports/soccer/usa.nwsl/")!

    // Base URL the scoreboard call builds on. As of V2 (0.2.0) this is the
    // caching proxy (AppConfig.scoreboardBaseURL) rather than `base`; teams,
    // roster, and standings still use `base`/the explicit standings URL.
    // Injectable so tests/previews can point it elsewhere.
    var scoreboardBase: URL = AppConfig.scoreboardBaseURL

    // Base URL the per-match `/summary` call builds on. ESPN direct for now
    // (the proxy `/summary` route is deferred — see AppConfig.summaryBaseURL);
    // injectable so tests/previews can point it elsewhere.
    var summaryBase: URL = AppConfig.summaryBaseURL

    // Base URL the per-athlete season-stats call builds on — ESPN's Core API
    // (a different host from `base`; see AppConfig.espnCoreBase). Injectable so
    // tests/previews can point it elsewhere.
    var statsBase: URL = AppConfig.espnCoreBase

    // Session-scoped cache for per-athlete season stats, shared so repeat team-page
    // visits don't refetch (see AthleteStatsCache). One per service instance.
    private let statsCache = AthleteStatsCache()

    // When `year` is provided, requests the full season via
    // `?dates=YYYY0101-YYYY1231&limit=500` — the form the API probe confirmed
    // returns the entire season (the default response caps at 100 events).
    //
    // `league` selects a non-NWSL competition via the proxy's `?league=<slug>`
    // allowlist (nil = NWSL, the default — no param, identical to before). Other
    // women's slugs (fifa.shebelieves, fifa.friendly.w, concacaf.w.gold, …) route
    // through the same cached pass-through; the proxy maps the slug to ESPN's path.
    func fetchScoreboard(year: Int? = nil, league: String? = nil) async throws -> Scoreboard {
        let endpoint = scoreboardBase.appendingPathComponent("scoreboard")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw ESPNServiceError.badURL
        }
        var items: [URLQueryItem] = []
        if let league { items.append(URLQueryItem(name: "league", value: league)) }
        if let year {
            items.append(URLQueryItem(name: "dates", value: "\(year)0101-\(year)1231"))
            items.append(URLQueryItem(name: "limit", value: "500"))
        }
        if !items.isEmpty { components.queryItems = items }
        guard let url = components.url else {
            throw ESPNServiceError.badURL
        }

        return try await fetch(Scoreboard.self, from: url)
    }

    // Fetches the league's club directory from the `teams` endpoint and returns
    // the flattened, alphabetically-sorted active clubs (see Club.swift).
    func fetchTeams() async throws -> [Club] {
        let url = base.appendingPathComponent("teams")
        return try await fetch(TeamsResponse.self, from: url).clubs
    }

    // Fetches the current league table from the standings endpoint and returns
    // the flattened, rank-sorted rows (see Standings.swift).
    //
    // Standings is the one endpoint NOT under `base`: it lives at `apis/v2/…`,
    // while everything else is `apis/site/v2/…` (the `site/v2` standings path
    // returns an empty object). So we build this URL explicitly rather than
    // appending to `base`.
    /// The season's phase calendar (ESPN core API `/seasons/{year}/types`): regular season +
    /// playoff-round date windows, published months ahead — drives the Schedule's year-round TBD
    /// playoff tail. The list is `$ref` links, so this derefs each (≤5 tiny GETs, once per launch
    /// via PlayoffStore). BEST-EFFORT: any failure → [] (the tail degrades to dateless TBD).
    func fetchSeasonWindows(year: Int) async -> [SeasonWindow] {
        guard let listURL = URL(string:
            "https://sports.core.api.espn.com/v2/sports/soccer/leagues/usa.nwsl/seasons/\(year)/types?limit=20")
        else { return [] }
        do {
            let list = try await fetch(SeasonTypeList.self, from: listURL)
            var windows: [SeasonWindow] = []
            for item in list.items ?? [] {
                guard let ref = item.ref,
                      let url = URL(string: ref.replacingOccurrences(of: "http://", with: "https://"))
                else { continue }
                if let window = try? await fetch(SeasonWindow.self, from: url) {
                    windows.append(window)
                }
            }
            return windows
        } catch {
            await Diagnostics.shared.record(.apiFailure, "seasonWindows \(year): \(error.localizedDescription)")
            return []
        }
    }

    /// The operator playoff override for a season (proxy `/playoff-override`). BEST-EFFORT: any
    /// failure (offline, 404, decode) returns nil so the bracket simply derives from ESPN — the
    /// override must never be able to break the feature it exists to protect.
    func fetchPlayoffOverride(season: Int) async -> PlayoffOverride? {
        guard let url = AppConfig.playoffOverrideURL(season: season) else { return nil }
        return try? await fetch(PlayoffOverrideEnvelope.self, from: url).override
    }

    // `season` fetches a PRIOR year's final table (the endpoint accepts `?season=YYYY`) —
    // used by PlayoffStore to seed a completed historical bracket in the offseason gap.
    // Omit for the current live table.
    func fetchStandings(season: Int? = nil) async throws -> [StandingsRow] {
        guard var components = URLComponents(string: "https://site.api.espn.com/apis/v2/sports/soccer/usa.nwsl/standings") else {
            throw ESPNServiceError.badURL
        }
        if let season { components.queryItems = [URLQueryItem(name: "season", value: "\(season)")] }
        guard let url = components.url else { throw ESPNServiceError.badURL }
        return try await fetch(StandingsResponse.self, from: url).rows
    }

    // Fetches one club's squad and returns a ClubSquad: the flattened athletes plus
    // the team profile (color, standing summary, record) that rides along in the same
    // payload (see Roster.swift). `clubID` is ESPN's team id — the stable `Club.id`,
    // not the abbreviation.
    //
    // Routes through the proxy's `GET /roster?team={id}` (AppConfig.rosterURL), which
    // adds last-known-good resilience for ESPN's recurring implausibly-small rosters
    // (and a `proxyCachedAsOf` marker when it serves the cache). DEBUG `-useESPNDirect`
    // bypasses the proxy and hits ESPN's `teams/{id}/roster` directly.
    func fetchRoster(clubID: String) async throws -> ClubSquad {
        guard let url = AppConfig.rosterURL(clubID: clubID) else {
            throw ESPNServiceError.badURL
        }
        return try await fetch(RosterResponse.self, from: url).squad
    }

    // Fetches one match's rich detail from `summary?event={id}` — lineups (with
    // formation), team match stats, and the key-events timeline (see
    // MatchSummary.swift). Built on `summaryBase` (ESPN direct for now) with the
    // event id as a query item, mirroring fetchScoreboard's URLComponents shape.
    func fetchSummary(eventID: String, nearKickoff: Bool = false) async throws -> MatchSummary {
        let endpoint = summaryBase.appendingPathComponent("summary")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw ESPNServiceError.badURL
        }
        components.queryItems = [URLQueryItem(name: "event", value: eventID)]
        // `w=near` is a CACHE-KEY-ONLY bucket (the proxy strips it before ESPN): inside the 2h
        // pre-kickoff lineup window it forks the proxy's edge-cache key, so a pre-lineup shell
        // cached HOURS earlier (with a TTL running to ~kickoff) can't mask a freshly posted XI —
        // the first near-window fetch is a guaranteed MISS under the proxy's short near TTL.
        if nearKickoff {
            components.queryItems?.append(URLQueryItem(name: "w", value: "near"))
        }
        guard let url = components.url else {
            throw ESPNServiceError.badURL
        }

        return try await fetch(MatchSummary.self, from: url)
    }

    // Fetches a past match's historical kickoff weather from the proxy's `/weather?event={id}`
    // (Open-Meteo behind it — ESPN has no NWSL weather). Additive/nice-to-have: the caller
    // (MatchDetailViewModel.loadWeather) treats any failure as "no stamp", never a screen error.
    // Proxy-only, so it uses AppConfig.weatherURL rather than a per-service base + -useESPNDirect.
    func fetchWeather(eventID: String) async throws -> MatchWeather {
        guard let url = AppConfig.weatherURL(eventID: eventID) else {
            throw ESPNServiceError.badURL
        }
        return try await fetch(MatchWeather.self, from: url)
    }

    // Fetches real season stats for a squad from ESPN's Core API — one call per
    // athlete (`…/seasons/{year}/types/1/athletes/{id}/statistics`), fanned out in
    // parallel. Replaces the former simulated StatsProvider; the call site in
    // TeamDetailViewModel is unchanged in shape.
    //
    // Deliberately NON-throwing and best-effort: stats are a secondary pass behind
    // the roster, so a failure must never break the team page. A per-athlete
    // failure (network/decode/non-2xx) drops just that player; a total outage
    // returns []. Results (including all-zero lines) are cached per athlete+year so
    // reopening a team page hits no network. `isGoalkeeper` comes from the roster
    // position, not from which stat categories ESPN returns.
    func seasonStats(for athletes: [Athlete],
                     year: Int = AppConfig.currentSeasonYear) async -> [PlayerSeasonStats] {
        await withTaskGroup(of: PlayerSeasonStats?.self) { group in
            for athlete in athletes {
                group.addTask {
                    if let cached = await self.statsCache.cached(athleteID: athlete.id, year: year) {
                        return cached
                    }
                    do {
                        let raw = try await self.fetchOneAthleteStats(id: athlete.id, year: year)
                        let stats = raw.playerSeasonStats(athleteID: athlete.id,
                                                          isGoalkeeper: athlete.isGoalkeeper)
                        await self.statsCache.store(stats, year: year)
                        return stats
                    } catch {
                        // Best-effort: a single bad athlete is omitted, not fatal.
                        return nil
                    }
                }
            }

            var results: [PlayerSeasonStats] = []
            for await stats in group {
                if let stats { results.append(stats) }
            }
            return results
        }
    }

    // One athlete's season-stats fetch — the season-scoped Core API path (the
    // no-season variant returns career totals). Path segments are appended one at a
    // time so the id is a single segment, mirroring fetchRoster.
    private func fetchOneAthleteStats(id: String, year: Int) async throws -> AthleteStatistics {
        let url = statsBase
            .appendingPathComponent("seasons")
            .appendingPathComponent("\(year)")
            .appendingPathComponent("types")
            .appendingPathComponent("1")          // 1 = Regular Season
            .appendingPathComponent("athletes")
            .appendingPathComponent(id)
            .appendingPathComponent("statistics")
        return try await fetch(AthleteStatistics.self, from: url)
    }

    // Shared GET-and-decode: one place for the status check and typed-error
    // wrapping, generic over whatever Decodable an endpoint returns.
    private func fetch<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        let (data, response) = try await session.data(from: url)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ESPNServiceError.badStatus(http.statusCode)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ESPNServiceError.decoding(error)
        }
    }
}
