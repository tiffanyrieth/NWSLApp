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

        // Proxy-outage resilience: on a proxy failure, retry the same query straight against
        // ESPN. NWSL only (league == nil) — a non-NWSL `?league=slug` is a proxy-only mapping
        // the app can't reproduce as an ESPN path.
        let espnDirect: URL? = {
            guard league == nil,
                  var c = URLComponents(url: base.appendingPathComponent("scoreboard"),
                                        resolvingAgainstBaseURL: false) else { return nil }
            if !items.isEmpty { c.queryItems = items }
            return c.url
        }()
        return try await fetch(Scoreboard.self, from: url, espnDirectFallback: espnDirect)
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
        // Proxy-outage resilience: on a proxy failure, hit ESPN's roster directly. This loses
        // the proxy's last-known-good cache (so a genuinely implausible ESPN squad shows as-is),
        // but an available roster beats a blank team page during a proxy outage.
        let espnDirect = base.appendingPathComponent("teams")
            .appendingPathComponent(clubID)
            .appendingPathComponent("roster")
        return try await fetch(RosterResponse.self, from: url, espnDirectFallback: espnDirect).squad
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

        // Proxy-outage resilience: retry ESPN direct on a proxy failure (event id only — the
        // `w=near` bucket is a proxy-cache hint ESPN doesn't need).
        let espnDirect: URL? = {
            guard var c = URLComponents(url: base.appendingPathComponent("summary"),
                                        resolvingAgainstBaseURL: false) else { return nil }
            c.queryItems = [URLQueryItem(name: "event", value: eventID)]
            return c.url
        }()
        return try await fetch(MatchSummary.self, from: url, espnDirectFallback: espnDirect)
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
        var fallback: NationalSquad?          // first non-empty squad seen, numbers or not
        var seen: [ClubSquad] = []            // every squad fetched, for the back-fill lookup
        var chosen: NationalSquad?

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
                guard !squad.athletes.isEmpty else { continue }
                seen.append(squad)
                let result = NationalSquad(squad: squad, feed: feed, teamID: teamID)
                if fallback == nil { fallback = result }
                if chosen == nil, squadHasNumbers(squad) { chosen = result }
                // Stop as soon as we hold a WELL-numbered squad. A sparse one keeps the loop going so
                // the remaining feeds can back-fill its blanks (below) — that costs extra requests, so
                // it is paid ONLY when the numbers are actually missing.
                if let chosen, numberedShare(chosen.squad) >= Self.wellNumberedShare { break }
            } catch {
                continue // a feed without this team/roster is EXPECTED — try the next, quietly
            }
        }

        guard let base = chosen ?? fallback else { return nil }
        return NationalSquad(squad: backfillJerseys(into: base.squad, from: seen),
                             feed: base.feed, teamID: base.teamID)
    }

    /// A squad this well numbered is good enough to stop looking; below it, keep fetching feeds so
    /// the blanks can be filled. 0.8 is chosen from measurement, not taste: every country swept on
    /// 2026-07-31 was either ~100% numbered (stop immediately — 9 of 12 gained NOTHING from a
    /// back-fill) or badly sparse (Japan: 5 of 26). Nothing sat in between, so the threshold buys
    /// Japan's fix without making the other 100+ countries pay for extra round-trips.
    private static let wellNumberedShare = 0.8

    private func numberedShare(_ squad: ClubSquad) -> Double {
        guard !squad.athletes.isEmpty else { return 0 }
        let n = squad.athletes.filter { $0.jersey?.isEmpty == false }.count
        return Double(n) / Double(squad.athletes.count)
    }

    /// Fill MISSING shirt numbers on the chosen squad from any other feed that has them, matched by
    /// ESPN athlete id.
    ///
    /// ⚠️ Deliberately NOT a squad merge. Unioning the feeds' PLAYER LISTS was measured and is plainly
    /// wrong — it produces 64 players for the USA and 52 for Brazil, i.e. everyone who has appeared in
    /// any competition across years, not a current squad (the same "season-cumulative" trap the NWSL
    /// roster work hit). Membership therefore comes from ONE feed, which is also what the page's
    /// "Squad · <feed>" label claims; only the per-player NUMBER is borrowed. Japan goes 5→22 of 26.
    func backfillJerseysForTesting(into squad: ClubSquad, from others: [ClubSquad]) -> ClubSquad {
        backfillJerseys(into: squad, from: others)
    }

    private func backfillJerseys(into squad: ClubSquad, from others: [ClubSquad]) -> ClubSquad {
        guard squad.athletes.contains(where: { $0.jersey?.isEmpty != false }) else { return squad }
        var byID: [String: String] = [:]
        for other in others {
            for a in other.athletes where a.jersey?.isEmpty == false {
                if byID[a.id] == nil { byID[a.id] = a.jersey }
            }
        }
        guard !byID.isEmpty else { return squad }
        let filled = squad.athletes.map { a -> Athlete in
            guard a.jersey?.isEmpty != false, let j = byID[a.id] else { return a }
            return Athlete(id: a.id, name: a.name, shortName: a.shortName, jersey: j,
                           positionName: a.positionName, positionAbbreviation: a.positionAbbreviation,
                           age: a.age, displayHeight: a.displayHeight, citizenship: a.citizenship)
        }
        return ClubSquad(athletes: filled, colorHex: squad.colorHex,
                         standingSummary: squad.standingSummary, record: squad.record,
                         cachedAsOf: squad.cachedAsOf)
    }

    /// True when the squad carries at least one shirt number. Deliberately "at least one", not "all":
    /// a real roster can legitimately have a gap (a just-called-up player without a number yet), and
    /// requiring every player to have one would reject a good feed over a single blank.
    func squadHasNumbers(_ squad: ClubSquad) -> Bool {
        squad.athletes.contains { ($0.jersey?.isEmpty == false) }
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

    // ESPN 403s UA-less / browser UAs but accepts honest HTTP-client UAs (the 2026-08-04
    // outage). The PROXY sends this UA; when we fall back to hitting ESPN directly we send it
    // too so ESPN can't reject us. (The app's default URLSession UA has worked for the always-
    // direct teams/standings calls, but we match the proxy to remove all doubt.)
    private static let espnDirectUA = "okhttp/4.9.0"

    // MARK: - Shared GET-and-decode (with proxy → ESPN-direct resilience)

    /// GET-and-decode with an optional proxy-outage fallback. `url` is the primary (proxy) URL.
    /// If it fails with a TRANSPORT error or a 5xx — a proxy-side problem, not a real 4xx/decode
    /// — and an `espnDirect` URL is supplied, we retry straight against ESPN (okhttp UA) so the
    /// CORE surfaces (scores/schedule/roster) survive a proxy outage the way the enriched Social/
    /// roster-verified paths can't. LOUD, never silent: emits a Diagnostics breadcrumb on
    /// fallback. A 4xx or decode error is not an outage → no retry (ESPN would answer the same).
    private func fetch<T: Decodable>(_ type: T.Type, from url: URL,
                                     espnDirectFallback espnDirect: URL? = nil) async throws -> T {
        do {
            return try await fetchOnce(type, from: url)
        } catch {
            guard let espnDirect, Self.isProxyOutage(error) else { throw error }
            await Diagnostics.shared.record(
                .apiFailure,
                "proxy unreachable (\(error.localizedDescription)) — recovered via ESPN-direct fallback: \(espnDirect.lastPathComponent)")
            return try await fetchOnce(type, from: espnDirect, userAgent: Self.espnDirectUA)
        }
    }

    /// One GET-and-decode. `userAgent`, when set, is sent as the request UA (the ESPN-direct
    /// fallback path); otherwise the session's default UA is used (the normal proxy path).
    private func fetchOnce<T: Decodable>(_ type: T.Type, from url: URL,
                                         userAgent: String? = nil) async throws -> T {
        let data: Data
        let response: URLResponse
        if let userAgent {
            var request = URLRequest(url: url)
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            (data, response) = try await session.data(for: request)
        } else {
            (data, response) = try await session.data(from: url)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ESPNServiceError.badStatus(http.statusCode)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ESPNServiceError.decoding(error)
        }
    }

    /// A proxy OUTAGE (retry ESPN direct) vs. a real error (don't): a transport failure
    /// (offline, DNS, timeout, connection lost) or a proxy 5xx is an outage; a 4xx or a decode
    /// error is not — ESPN would fail the same way, so retrying just doubles the latency.
    private static func isProxyOutage(_ error: Error) -> Bool {
        if error is URLError { return true }
        if case ESPNServiceError.badStatus(let code) = error { return code >= 500 }
        return false
    }
}
