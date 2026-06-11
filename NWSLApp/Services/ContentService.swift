//
//  ContentService.swift
//  NWSLApp
//
//  The app-side client for the ALIVE content pipeline (Part 2). It fetches the
//  proxy's content routes and decodes `[ContentCard]` — all the discovery,
//  unfurling, caching, and AI tagging live in the `nwslapp-proxy` Worker, so the
//  app stays thin (it just decodes the already-normalized cards). Mirrors
//  `ESPNService`: a `URLSession`, a typed error, a small generic fetch.
//
//  SCAFFOLD STATE (Part 2 Step 1): the live `/team-videos` route is not deployed
//  yet (it needs the owner's YouTube Data API key as a Worker secret), so
//  `AppConfig.liveContentEnabled` is `false` and every call here falls through to
//  the Part-1 ⚠️seed providers — Home renders exactly as today. The live path is
//  fully written and compiled; flipping `liveContentEnabled` (once the route is
//  live) switches Home to real channel uploads with no further app changes. A
//  proxy failure ALSO falls back to seed (offline-first — the hook never goes blank).
//
//  WHEN REMOVED: nothing to remove — when the seed providers retire, this keeps the
//  same signatures and only the fallback branch goes away. DEBUG `-useSeedContent`
//  forces the seed (the escape hatch, mirroring `-useESPNDirect`).
//

import Foundation

enum ContentServiceError: Error {
    case badStatus(Int)
    case decoding(Error)
    case badURL
}

struct ContentService {
    var session: URLSession = .shared

    /// The Part-1 seeds, used as the fallback (and the only source while
    /// `liveContentEnabled` is false). Injectable for tests/previews. `seed` backs
    /// Home (`homeCards`); `seedFeed` backs the Feed (`feedCards`).
    var seed = TeamContentProvider()
    var seedFeed = FeedContentProvider()

    /// Home Module-1 cards for the followed clubs. Live: the proxy `/team-videos`
    /// route (recent YouTube uploads, normalized to `ContentCard`); today: the
    /// curated seed. Any failure degrades to the seed so the hook never goes blank.
    /// (The returned set may span more teams than `followedAbbreviations`; the
    /// caller's `HomeViewModel.teamContent` filters + applies staleness as before.)
    func homeCards(followedAbbreviations: Set<String>) async -> [ContentCard] {
        guard AppConfig.liveContentEnabled, !forceSeed else {
            return await seed.items()
        }
        do {
            return try await fetchTeamVideos(Array(followedAbbreviations))
        } catch {
            // Offline-first: a proxy hiccup falls back to the seed, never an empty
            // module. (The error is intentionally swallowed — the seed is a valid
            // answer, not a failure state, for the lead module.)
            return await seed.items()
        }
    }

    /// Feed-tab cards for the followed clubs. Live: the proxy `/feed` route
    /// (reporter + league + followed-team Bluesky posts, normalized to
    /// `ContentCard`); today's fallback: the curated seed. Any failure degrades to
    /// the seed so the Feed never goes blank. The returned set is filtered (by chip,
    /// follows, preferences) and 7-day-staleness-windowed by `FeedViewModel`.
    func feedCards(followedAbbreviations: Set<String>) async -> [ContentCard] {
        guard AppConfig.liveContentEnabled, !forceSeed else {
            return await seedFeed.items()
        }
        do {
            return try await fetchFeed(Array(followedAbbreviations))
        } catch {
            // Offline-first: a proxy hiccup falls back to the seed, never an empty
            // Feed. (The seed is a valid answer, not a failure state.)
            return await seedFeed.items()
        }
    }

    // MARK: - Live fetch

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

    /// DEBUG escape hatch: `-useSeedContent` in the Run scheme forces the seed even
    /// when the live pipeline is enabled (mirrors `-useESPNDirect`).
    private var forceSeed: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-useSeedContent")
        #else
        return false
        #endif
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
