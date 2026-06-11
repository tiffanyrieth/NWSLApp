//
//  AppConfig.swift
//  NWSLApp
//
//  One source of truth for the app's base URLs. As of V2 (0.2.0) the
//  full-season scoreboard is served through a tiny Cloudflare Worker
//  (`nwslapp-proxy`) that fetches ESPN once, caches it, and fans out to all
//  callers (see CLAUDE.md → "Data Source" and What's-Next #12). Everything
//  else still hits ESPN directly.
//
//  These URLs are public (the `*.workers.dev` host is not a secret), so they
//  live in a plain checked-in file. The gitignored-secrets pattern arrives in
//  0.3.0 alongside Supabase keys.
//

import Foundation

enum AppConfig {
    /// ESPN's unofficial NWSL API root. Still backs teams, roster, and
    /// (via an explicit `apis/v2` URL in ESPNService) standings.
    /// Force-unwrap is safe: a compile-time constant, valid URL.
    static let espnBase = URL(string: "https://site.api.espn.com/apis/site/v2/sports/soccer/usa.nwsl/")!

    /// ESPN's "Core" API root (a *different* host from `espnBase`), which serves
    /// per-athlete season statistics at
    /// `seasons/{year}/types/1/athletes/{id}/statistics`. Hit directly for now,
    /// like teams/roster/standings; a caching proxy `statsBaseURL` route is a
    /// future follow-up (CLAUDE.md What's-Next #6).
    /// Force-unwrap is safe: a compile-time constant, valid URL.
    static let espnCoreBase = URL(string: "https://sports.core.api.espn.com/v2/sports/soccer/leagues/usa.nwsl/")!

    /// The season the app reads player stats for. Hardcoded to the current season;
    /// a stale value silently returns empty stats league-wide (no crash). Centralized
    /// here so the yearly fix is one line.
    /// TODO (#6): resolve dynamically from the league root's `season.year`
    /// (`GET …/leagues/usa.nwsl` → `season.year`).
    static let currentSeasonYear = 2026

    /// The deployed caching proxy. `GET /scoreboard` here forwards the query
    /// string to ESPN's scoreboard endpoint and returns the bytes unchanged,
    /// so the app's `Scoreboard` decoder needs no changes.
    /// Force-unwrap is safe: a compile-time constant, valid URL.
    static let scoreboardProxyBase = URL(string: "https://nwslapp-proxy.tiffany-rieth.workers.dev/")!

    /// Base URL the scoreboard call builds on. The proxy by default; in DEBUG,
    /// passing `-useESPNDirect` in the Run scheme's launch arguments falls back
    /// to hitting ESPN directly — a quick escape hatch if the proxy misbehaves,
    /// mirroring the `-resetOnboarding` launch-arg precedent in NWSLAppApp.swift.
    static var scoreboardBaseURL: URL {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-useESPNDirect") {
            return espnBase
        }
        #endif
        return scoreboardProxyBase
    }

    /// Base URL the per-match `/summary` call builds on. As of 0.3.1 the proxy's
    /// `GET /summary` route is live — it forwards `?event={id}` to ESPN and
    /// caches with a match-state-aware TTL (a finished match is immutable, a live
    /// one 30s, a future one until the next 3am ET), so popular past matches no
    /// longer re-hit ESPN on every tap. The bytes are returned unchanged, so the
    /// `MatchSummary` decoder is untouched. In DEBUG, `-useESPNDirect` falls back
    /// to hitting ESPN directly, exactly like `scoreboardBaseURL`.
    static var summaryBaseURL: URL {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-useESPNDirect") {
            return espnBase
        }
        #endif
        return scoreboardProxyBase
    }

    // MARK: - Live content (ALIVE pipeline — Part 2)

    /// Master switch for the live content pipeline (YouTube → Home, then
    /// Bluesky/Reddit/news → Feed). **OFF until the proxy content routes are
    /// deployed** (the `/team-videos` route needs the owner's YouTube Data API key
    /// set as a Worker secret first — see `content-cards-part2-live-data.md`).
    /// While false, `ContentService` serves the Part-1 ⚠️seed providers, so Home/
    /// Feed render exactly as today. Flip to `true` once the route is live — one line.
    static let liveContentEnabled = true

    /// The proxy route that returns Home Module-1 cards as `ContentCard` JSON:
    /// `GET /team-videos?teams=WAS,POR,…`. The Worker resolves each club's YouTube
    /// uploads playlist, fetches recent uploads via the YouTube Data API, and
    /// normalizes them to the `ContentCard` shape (so the app just decodes).
    /// Built on the same proxy host as the scoreboard. Returns nil on a malformed
    /// query (caller falls back to seed). `teams` is the followed-club abbreviations.
    static func teamVideosURL(teams: [String]) -> URL? {
        contentRouteURL("team-videos", teams: teams)
    }

    /// The proxy route powering the Feed tab: `GET /feed?teams=WAS,POR,…`. The
    /// Worker fans out the curated Bluesky handles — reporters + league outlets
    /// always, plus each requested club's own account — and normalizes posts to
    /// `ContentCard` JSON (reporter/league → `blueskyReporter`; a club's own posts
    /// → `blueskyTeam{Media,Text}` with placement `.both`, so they ALSO surface on
    /// Home). `teams` is the followed-club abbreviations, which scope the team
    /// posts (reporters/league come back regardless). Returns nil on a malformed
    /// query (caller falls back to seed). A2 of the live Feed; Reddit + news RSS
    /// extend this same route later. Mirrors `teamVideosURL`.
    static func feedURL(teams: [String]) -> URL? {
        contentRouteURL("feed", teams: teams)
    }

    /// Shared builder for the `?teams=…` content routes (`/team-videos`, `/feed`):
    /// appends the path to the proxy host and the comma-joined team list, omitting
    /// the query entirely when no teams are given. Returns nil on a malformed URL.
    private static func contentRouteURL(_ path: String, teams: [String]) -> URL? {
        let endpoint = scoreboardProxyBase.appendingPathComponent(path)
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            return nil
        }
        if !teams.isEmpty {
            components.queryItems = [URLQueryItem(name: "teams", value: teams.joined(separator: ","))]
        }
        return components.url
    }
}
