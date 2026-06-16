//
//  ContentService.swift
//  NWSLApp
//
//  The app-side client for the ALIVE content pipeline. It fetches the proxy's
//  content routes and decodes `[ContentCard]` — all the discovery, unfurling,
//  caching, and AI tagging live in the `nwslapp-proxy` Worker, so the app stays
//  thin (it just decodes the already-normalized cards). Mirrors `ESPNService`:
//  a `URLSession`, a typed error, a small generic fetch.
//
//  ONLINE-ONLY: the app is built to run against a live connection — there is no
//  offline mode and NO runtime seed. Every method here `throws`; a failed fetch
//  SURFACES so the caller can show an honest "Couldn't load — tap to retry". There
//  is deliberately no seed/sample fallback: a curated stand-in that renders like the
//  real thing is indistinguishable from live data and hides breakage (it was
//  repeatedly mistaken for the live build). Seed/fixture data now lives ONLY in the
//  test target and SwiftUI previews, where it can never run as the shipping app.
//

import Foundation

enum ContentServiceError: Error {
    case badStatus(Int)
    case decoding(Error)
    case badURL
}

struct ContentService {
    var session: URLSession = .shared

    /// Home Module-1 cards for the followed clubs — the proxy `/team-videos` route
    /// (recent YouTube uploads + club OG news + club IG, normalized to `ContentCard`).
    /// Throws on any failure; the caller surfaces an honest error (no seed fallback).
    /// (The returned set may span more teams than `followedAbbreviations`; the
    /// caller's `HomeViewModel.teamContent` filters + applies staleness as before.)
    func homeCards(followedAbbreviations: Set<String>) async throws -> [ContentCard] {
        try await fetchTeamVideos(Array(followedAbbreviations))
    }

    /// Feed-tab cards for the followed clubs — the proxy `/feed` route (reporter +
    /// league + followed-team Bluesky/news, normalized to `ContentCard`). Throws on
    /// any failure (no seed fallback). The returned set is filtered (by chip, follows,
    /// preferences) and 7-day-staleness-windowed by `FeedViewModel`.
    func feedCards(followedAbbreviations: Set<String>) async throws -> [ContentCard] {
        try await fetchFeed(Array(followedAbbreviations))
    }

    /// Home Module-2 spotlights for the followed clubs — the proxy `/spotlight` route
    /// (one real player per team from the recent matchday squad, real season stats, a
    /// Haiku "why watch" blurb). Throws on any failure (no seed fallback).
    /// `HomeViewModel.spotlights(following:)` then picks one per followed team.
    func spotlightCards(followedAbbreviations: Set<String>) async throws -> [PlayerSpotlight] {
        try await fetchSpotlights(Array(followedAbbreviations))
    }

    // MARK: - Live fetch

    private func fetchSpotlights(_ teams: [String]) async throws -> [PlayerSpotlight] {
        guard let url = AppConfig.spotlightURL(teams: teams) else {
            throw ContentServiceError.badURL
        }
        return try await fetch([PlayerSpotlight].self, from: url)
    }

    private func fetchTeamVideos(_ teams: [String]) async throws -> [ContentCard] {
        guard let url = AppConfig.teamVideosURL(teams: teams) else {
            throw ContentServiceError.badURL
        }
        return try await fetch([ContentCard].self, from: url)
    }

    private func fetchFeed(_ teams: [String]) async throws -> [ContentCard] {
        guard let url = AppConfig.feedURL(teams: teams) else {
            throw ContentServiceError.badURL
        }
        return try await fetch([ContentCard].self, from: url)
    }

    private func fetch<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        let (data, response) = try await session.data(from: url)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ContentServiceError.badStatus(http.statusCode)
        }

        do {
            // The proxy emits ISO-8601 timestamps; `ContentCard.timestamp` is a Date.
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(T.self, from: data)
        } catch {
            throw ContentServiceError.decoding(error)
        }
    }
}
