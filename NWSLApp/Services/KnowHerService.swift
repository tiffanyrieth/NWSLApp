//
//  KnowHerService.swift
//  NWSLApp
//
//  The app-side client for the LIVE Know Her Game pool — the Fan Zone game's twin of
//  `TriviaService`. Fetches the proxy's `GET /knowher?teams=` route (the owner-loaded
//  weekly pool from KV, filtered to followed teams) and decodes a `KnowHerPool`.
//
//  ONLINE-ONLY (mirrors `TriviaService`): no runtime seed. `pool(teams:)` `throws` on any
//  failure — a disabled connection, a network/proxy error, or an EMPTY pool (no featured
//  player for any followed team, e.g. the offseason). The caller then hides the game
//  rather than showing a stale or fabricated player. The seed lives only in the test target.
//

import Foundation

/// Know-Her-specific failure: the live pool came back with no players (nothing to play).
enum KnowHerServiceError: Error {
    case emptyPool
}

struct KnowHerService {
    var session: URLSession = .shared

    /// The weekly pool for the given followed teams. Throws on any failure or an empty pool
    /// so the game never renders stale/fabricated content.
    func pool(teams: [String]) async throws -> KnowHerPool {
        guard let url = AppConfig.knowHerURL(teams: teams) else {
            throw ContentServiceError.badURL
        }
        let live = try await fetch(KnowHerPool.self, from: url)
        guard !live.players.isEmpty else { throw KnowHerServiceError.emptyPool }
        return live
    }

    private func fetch<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ContentServiceError.badStatus(http.statusCode)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ContentServiceError.decoding(error)
        }
    }
}
