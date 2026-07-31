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
    // `dates` (e.g. "20260710-20260712") overrides the year-derived full-season range — used by the
    // live poll to fetch a small yesterday→tomorrow WINDOW instead of re-downloading the ~2MB season
    // every 30s (and the window stays fresh at ESPN, unlike the laggy full-season query). nil = the
    // original year-based behavior, unchanged for every existing caller.
    func fetchScoreboard(year: Int? = nil, league: String? = nil, dates: String? = nil) async throws -> Scoreboard {
        let endpoint = scoreboardBase.appendingPathComponent("scoreboard")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw ESPNServiceError.badURL
        }
        var items: [URLQueryItem] = []
        if let league { items.append(URLQueryItem(name: "league", value: league)) }
        if let dates {
            items.append(URLQueryItem(name: "dates", value: dates))
            items.append(URLQueryItem(name: "limit", value: "500"))
        } else if let year {
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
    /// `quietMisses`: the NATIONAL-TEAM player path sets this — most NT players have no NWSL
    /// line, so a fetch failure there is the expected "not in NWSL" answer, not an incident.
    /// Logging it would flood Diagnostics with false apiFailures (the same bug the doomed
    /// club-roster fetch had on NT lineups). Club paths keep full logging.
    func seasonStats(for athletes: [Athlete],
                     year: Int = AppConfig.currentSeasonYear,
                     quietMisses: Bool = false) async -> [PlayerSeasonStats] {
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
                    } catch is CancellationError {
                        return nil   // caller navigated away — expected, don't log
                    } catch let error as URLError where error.code == .cancelled {
                        return nil   // URLSession's cancellation shape — also expected
                    } catch {
                        // Best-effort: a single bad athlete is omitted, not fatal — but NOT
                        // silently (no-silent-failures rule). A genuine failure is logged so a
                        // blank stats card is diagnosable rather than looking like "no stats".
                        if !quietMisses {
                            Diagnostics.shared.record(.apiFailure,
                                "season stats \(athlete.id) (\(year)): \(error.localizedDescription)")
                        }
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

    // MARK: - National teams (live, ESPN-as-is)
    //
    // ⚠️ The deliberate INVERSE of the NWSL roster stack (docs/national-teams.md §0). NWSL
    // rosters are stored, verified nightly against the league feed, and owner-corrected,
    // because the app has both a second source and an authority to appeal to. National teams
    // have neither, and the owner's accepted trade is ESPN-AS-IS: everything here is fetched
    // live at view time, device→ESPN direct — no proxy layer, no KV, no cron, nothing stored,
    // so nothing can go stale and there is nothing to monitor. Do not "harden" this path with
    // caches or cross-checks without reopening that decision.

    /// A country's current squad plus which competition feed supplied it.
    struct NationalSquad {
        let squad: ClubSquad
        let feed: NationalTeamFeed
        let teamID: String
    }

    private func ntSiteBase(_ slug: String) -> URL? {
        URL(string: "https://site.api.espn.com/apis/site/v2/sports/soccer/\(slug)/")
    }

    /// Minimal decode of a feed's `/teams` — just enough to join by FIFA code.
    private struct NTTeamsList: Decodable {
        struct Sport: Decodable { let leagues: [League]? }
        struct League: Decodable { let teams: [Entry]? }
        struct Entry: Decodable { let team: Team? }
        struct Team: Decodable { let id: String?; let abbreviation: String? }
        let sports: [Sport]?

        func teamID(code: String) -> String? {
            sports?.first?.leagues?.first?.teams?
                .first { $0.team?.abbreviation?.uppercased() == code.uppercased() }?.team?.id
        }
    }

    /// The country's squad from the FIRST feed that carries one, in `NationalTeamFeed.all`
    /// order — friendlies first, deliberately: the friendlies list is the BROADEST squad
    /// picture, where a tournament feed carries only that tournament's registered squad
    /// (measured 2026-07-31: Zambia = 26 via friendlies, 23 via the World Cup feed). Match
    /// screens keep using the match's own lineup either way.
    ///
    /// ⚠️ Team ids are PER-WOMEN'S-PROGRAM, not the famous men's ids — USWNT is 2765 in these
    /// feeds, not 660. Always join by FIFA code via the feed's own `/teams`; assuming an id
    /// produced a false "USWNT has no roster" during research.
    ///
    /// nil = NO feed has a squad. The caller shows an honest empty state — never fabricates.
    func nationalTeamSquad(code: String) async -> NationalSquad? {
        let feeds = NationalTeamFeed.scopedFeeds(forFollowedCodes: [code]).feeds
        for feed in feeds {
            guard let base = ntSiteBase(feed.slug) else { continue }
            do {
                let list = try await fetch(NTTeamsList.self, from: base.appendingPathComponent("teams"))
                guard let teamID = list.teamID(code: code) else { continue }
                let squad = try await fetch(
                    RosterResponse.self,
                    from: base.appendingPathComponent("teams")
                        .appendingPathComponent(teamID)
                        .appendingPathComponent("roster")
                ).squad
                if !squad.athletes.isEmpty {
                    return NationalSquad(squad: squad, feed: feed, teamID: teamID)
                }
            } catch {
                continue // a feed without this team/roster is EXPECTED — try the next, quietly
            }
        }
        return nil
    }

    /// Bio fields for one athlete, competition-scoped (works for players NOT in NWSL — the
    /// club-roster path can't reach them). BIO-ONLY on purpose: the same record carries the
    /// athlete's CLUB jersey and position, which must never overwrite the match-specific
    /// values (her national-team number and role differ from her club's — Kundananji is Bay
    /// FC #9 and Zambia #17).
    struct AthleteBio: Decodable {
        let age: Int?
        let displayHeight: String?
        let citizenship: String?
    }

    func athleteBio(leagueSlug: String, athleteID: String) async throws -> AthleteBio {
        guard let url = URL(
            string: "https://sports.core.api.espn.com/v2/sports/soccer/leagues/\(leagueSlug)/athletes/\(athleteID)"
        ) else { throw ESPNServiceError.badURL }
        return try await fetch(AthleteBio.self, from: url)
    }

    /// One athlete's stat line for a specific COMPETITION (e.g. WAFCON) — same Core API shape
    /// as the NWSL season fetch, different league scope. Verified live 2026-07-31 (Banda:
    /// 4 goals in the WAFCON opener). Best-effort like `seasonStats`; a miss returns nil and
    /// does NOT log — a player with no line in this tournament is expected, not a failure.
    /// Deliberately NOT routed through `AthleteStatsCache`: its key is (athleteID, year), so
    /// caching a WAFCON line there would collide with the player's NWSL line.
    func tournamentStats(for athlete: Athlete, leagueSlug: String,
                         year: Int = AppConfig.currentSeasonYear) async -> PlayerSeasonStats? {
        guard let url = URL(
            string: "https://sports.core.api.espn.com/v2/sports/soccer/leagues/\(leagueSlug)/seasons/\(year)/types/1/athletes/\(athlete.id)/statistics"
        ) else { return nil }
        guard let raw = try? await fetch(AthleteStatistics.self, from: url) else { return nil }
        return raw.playerSeasonStats(athleteID: athlete.id, isGoalkeeper: athlete.isGoalkeeper)
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
