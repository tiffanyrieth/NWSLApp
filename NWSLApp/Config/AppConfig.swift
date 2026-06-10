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
}
