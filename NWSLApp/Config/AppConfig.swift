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
    /// ESPN's unofficial NWSL API root. Still backs teams and (via an explicit
    /// `apis/v2` URL in ESPNService) standings; roster now routes through the proxy
    /// (`rosterURL`), with DEBUG `-useESPNDirect` falling back to this base.
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

    /// The proxy route serving a club's squad: `GET /roster?team=<espnTeamId>`. The Worker
    /// passes ESPN's roster through when it's a plausible squad (caching it as last-known-good),
    /// and falls back to that cache — adding a top-level `proxyCachedAsOf` marker — when ESPN
    /// returns an implausibly small roster (the recurring "one player" gap on some teams). The
    /// bytes are otherwise ESPN's, so `RosterResponse` decodes them unchanged. `clubID` is
    /// ESPN's team id. In DEBUG, `-useESPNDirect` bypasses the proxy and hits ESPN's
    /// `teams/{id}/roster` directly (no cache/marker), mirroring `scoreboardBaseURL`.
    /// Returns nil on a malformed URL (the caller then throws → honest error).
    static func rosterURL(clubID: String) -> URL? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-useESPNDirect") {
            return espnBase
                .appendingPathComponent("teams")
                .appendingPathComponent(clubID)
                .appendingPathComponent("roster")
        }
        #endif
        guard var components = URLComponents(url: scoreboardProxyBase.appendingPathComponent("roster"),
                                             resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = [URLQueryItem(name: "team", value: clubID)]
        return components.url
    }

    // MARK: - Live content (ALIVE pipeline)

    /// The proxy route that returns Home Module-1 cards as `ContentCard` JSON:
    /// `GET /team-videos?teams=WAS,POR,…`. The Worker resolves each club's YouTube
    /// uploads playlist, fetches recent uploads via the YouTube Data API, and
    /// normalizes them to the `ContentCard` shape (so the app just decodes).
    /// Built on the same proxy host as the scoreboard. Returns nil on a malformed
    /// query (the caller then throws → honest error). `teams` is the followed-club abbreviations.
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
    /// query (the caller then throws → honest error). Reddit + news RSS extend this
    /// same route later. Mirrors `teamVideosURL`.
    static func feedURL(teams: [String]) -> URL? {
        contentRouteURL("feed", teams: teams)
    }

    /// The proxy route powering Home Module 2 "Get to know your players":
    /// `GET /spotlight?teams=WAS,POR,…` (B2). The Worker picks one real player from
    /// each followed club's most recent matchday squad, attaches real ESPN season
    /// stats, and generates a short "why watch" blurb via Haiku — returning
    /// `PlayerSpotlight` JSON the app decodes directly. Returns nil on a malformed
    /// query (the caller then throws → honest error). Mirrors `teamVideosURL`/`feedURL`.
    static func spotlightURL(teams: [String]) -> URL? {
        contentRouteURL("spotlight", teams: teams)
    }

    /// The proxy route powering Fan Zone Daily Trivia: `GET /trivia`. Unlike the
    /// other content routes, Daily Trivia is **league-wide** (one shared question
    /// pool, not team-scoped — see `games-design-spec.md`), so this builds with no
    /// `teams` query at all. The Worker returns the owner-loaded `[TriviaQuestion]`
    /// pool from KV; the app does the deterministic daily-5 selection client-side.
    /// An empty or unreachable route surfaces an honest error (no seed fallback).
    /// Returns nil on a malformed URL (the caller then throws → honest error).
    static func triviaURL() -> URL? {
        contentRouteURL("trivia", teams: [])
    }

    /// The proxy route powering Fan Zone "Know Her Game": `GET /knowher?teams=WAS,POR,…`.
    /// The Worker returns the owner-loaded weekly pool (KV) filtered to the followed teams —
    /// one featured player per team, each with a guardrailed Q&A set (docs/know-her-game.md).
    /// Team-scoped (unlike `/trivia`), so it takes the followed-club abbreviations. An empty or
    /// unreachable route surfaces an honest error and the game hides (online-only, no seed).
    /// Returns nil on a malformed URL (the caller then throws → honest error).
    static func knowHerURL(teams: [String]) -> URL? {
        contentRouteURL("knowher", teams: teams)
    }

    /// The proxy route serving the community-results distribution for a quiz edition:
    /// `GET /quiz-results?game=trivia|knowher&edition=<key>`. Shared by NWSL Trivia + Know Her
    /// Game (docs §11b) — the leaderboard REPLACEMENT. The Worker computes the aggregate from
    /// Supabase (as service_role) and serves it from its edge cache; the app never aggregates.
    /// Returns nil on a malformed URL.
    static func quizResultsURL(game: String, edition: String) -> URL? {
        let endpoint = scoreboardProxyBase.appendingPathComponent("quiz-results")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "game", value: game),
            URLQueryItem(name: "edition", value: edition),
        ]
        return components.url
    }

    // MARK: - Match weather

    /// The proxy route serving a past match's historical kickoff weather:
    /// `GET /weather?event=<espnEventId>` (Open-Meteo behind it — see nwslapp-proxy/src/weather.ts).
    /// Proxy-only by design: there is no ESPN equivalent (ESPN carries no NWSL weather), so unlike
    /// `summaryBaseURL` there is deliberately NO `-useESPNDirect` fallback. Returns nil on a bad URL.
    static func weatherURL(eventID: String) -> URL? {
        let endpoint = scoreboardProxyBase.appendingPathComponent("weather")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = [URLQueryItem(name: "event", value: eventID)]
        return components.url
    }

    /// The proxy route serving the operator PLAYOFF OVERRIDE for a season: `GET
    /// /playoff-override?season=YYYY` → `{ version, season, override }`. Dormant (override null)
    /// unless set. PlayoffStore fetches it best-effort and layers it over the ESPN-derived bracket.
    static func playoffOverrideURL(season: Int) -> URL? {
        let endpoint = scoreboardProxyBase.appendingPathComponent("playoff-override")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = [URLQueryItem(name: "season", value: "\(season)")]
        return components.url
    }

    // MARK: - Team crests

    /// The proxy route serving a team's NWSL crest as a transparent PNG: `GET /crest?team=WAS`.
    /// `TeamLogo` prefers this crisp crest and falls back to the ESPN raster when the team isn't
    /// loaded (404). Keyed by the app's team abbreviation. Returns nil on a malformed URL.
    static func crestURL(abbreviation: String) -> URL? {
        guard var components = URLComponents(url: scoreboardProxyBase.appendingPathComponent("crest"),
                                             resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = [URLQueryItem(name: "team", value: abbreviation.uppercased())]
        return components.url
    }

    /// The proxy route serving the asset version manifest: `GET /crest/manifest` →
    /// `{ crests: {ABBR: hash}, flags: {CODE: hash} }`. `AssetRefreshService` fetches this
    /// on a cadence (>30d / forced in March) and re-downloads only an asset whose hash drifts
    /// from what was bundled (a rebrand). Returns nil on a malformed URL.
    static func assetManifestURL() -> URL? {
        scoreboardProxyBase.appendingPathComponent("crest/manifest")
    }

    /// A national-team flag as a raster PNG from flagcdn, for the post-rebrand cache OVERRIDE
    /// only (the bundled flag is a crisper vector; a downloaded SVG can't be drawn from disk,
    /// so the override is a high-res raster). Keyed by the flagcdn slug. Returns nil on a
    /// malformed URL.
    static func flagRasterURL(slug: String) -> URL? {
        URL(string: "https://flagcdn.com/w1280/\(slug).png")
    }

    /// The proxy route serving the data-driven women's national-team directory: `GET
    /// /national-teams` → `[{code, name, flag}]` (the union of ESPN coverage). Backs the
    /// "Browse all" list so it reflects real coverage, not a hand-maintained set. Returns nil on
    /// a malformed URL.
    static func nationalTeamsURL() -> URL? {
        scoreboardProxyBase.appendingPathComponent("national-teams")
    }

    /// The proxy route that collects the app's no-silent-failure telemetry: `POST /telemetry`.
    /// Diagnostics flushes a small batch of NON-PII operational events here so a field miss
    /// reaches the owner without a user report. Returns nil on a malformed URL.
    static func telemetryURL() -> URL? {
        scoreboardProxyBase.appendingPathComponent("telemetry")
    }

    // MARK: - Forced-update version gate

    /// The proxy route the app checks at launch: `GET /config` → `{ minVersion, minBuild }`. If this
    /// build's `CFBundleVersion` is below `minBuild`, the app shows a non-dismissible update wall. The
    /// check FAILS OPEN — an unreachable proxy never blocks the app (see `ForceUpdateService`).
    static func configURL() -> URL? {
        scoreboardProxyBase.appendingPathComponent("config")
    }

    /// Where the update wall's "Update" button sends the user. TestFlight for now (beta distribution);
    /// swap to the App Store product URL at public launch. `itms-beta://` opens the TestFlight app so the
    /// tester can install the newer build; replace with the app's public TestFlight join link
    /// (`https://testflight.apple.com/join/<code>`) for a direct deep-link.
    /// Force-unwrap is safe: a compile-time constant, valid URL.
    static let updateURL = URL(string: "itms-beta://")!

    // MARK: - Player headshots

    /// The proxy route returning the `{ espnAthleteId: nwslGuid }` headshot map as JSON:
    /// `GET /headshots`. League-wide (no `teams`), like `/trivia`. The Worker name-matches
    /// NWSL players to ESPN athlete ids on a weekly cron; the app fetches this map once
    /// (`HeadshotStore`) and builds the Cloudinary image URL on-device (`headshotImageURL`).
    /// Returns nil on a malformed URL (caller then shows monograms everywhere).
    static func headshotsMapURL() -> URL? {
        contentRouteURL("headshots", teams: [])
    }

    /// The on-device size for a headshot, mapped to a Cloudinary width transform. The CDN is
    /// named-transform-only, so these are the *verified-working* widths: `t_w_240` covers the
    /// ≤48pt circular avatars (3× Retina), `t_w_480` the 96pt player-detail hero. (`t_w_360`
    /// 400s — do NOT add it.)
    enum HeadshotSize {
        case card   // ≤48pt avatars: squad cards, Spotlight, pitch/bracket dots, picker slots
        case detail // 96pt PlayerDetailView hero

        var cloudinaryWidth: Int {
            switch self {
            case .card: return 240
            case .detail: return 480
            }
        }
    }

    /// Build the NWSL Cloudinary headshot URL for a player GUID at a given size. A player with
    /// no photo on file 404s, so `ImageCache` returns nil and the caller keeps its monogram —
    /// no fallbacklogo detection needed. Returns nil on a malformed URL.
    static func headshotImageURL(guid: String, size: HeadshotSize) -> URL? {
        URL(string: "https://images.nwslsoccer.com/image/private/t_w_\(size.cloudinaryWidth)/prd/assets/widgets/players/\(guid)")
    }

    /// Shared builder for the content routes (`/team-videos`, `/feed`, `/spotlight`,
    /// `/trivia`, `/headshots`): appends the path to the proxy host and the comma-joined team
    /// list, omitting the query entirely when no teams are given (as `/trivia`/`/headshots`
    /// always are). Returns nil on a malformed URL.
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
