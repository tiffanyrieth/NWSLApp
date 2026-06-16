//
//  TriviaService.swift
//  NWSLApp
//
//  The app-side client for the LIVE Daily-Trivia question pool — the Fan Zone
//  game's equivalent of `ContentService`. It fetches the proxy's `/trivia` route
//  (the owner-loaded question pool, served from the Worker's KV) and decodes
//  `[TriviaQuestion]`; the deterministic daily-5 selection stays in
//  `TriviaViewModel`, and the durable streak/accuracy state stays in `TriviaStore`.
//
//  ONLINE-ONLY (mirrors `ContentService`): no runtime seed. `triviaQuestions()`
//  `throws` on any failure — a disabled connection, a network/proxy error, or an
//  EMPTY pool (a quiz with no questions can't be played, so an empty response is a
//  failure, not a valid answer). The caller shows an honest "Couldn't load — tap to
//  retry" rather than silently swapping in a bundled question bank that's
//  indistinguishable from the live pool. The seed bank lives only in the test target.
//

import Foundation

/// Trivia-specific failure: the live pool came back empty (no questions to play).
/// Distinct from a transport/decoding error so the caller can message it the same
/// honest way (it's still "couldn't load a playable quiz").
enum TriviaServiceError: Error {
    case emptyPool
}

struct TriviaService {
    var session: URLSession = .shared

    /// The full question pool from the proxy `/trivia` route (the owner-loaded pool
    /// from KV). Throws on any failure — disabled connection, network error, or an
    /// empty response — so the game never silently falls back to a bundled bank.
    func triviaQuestions() async throws -> [TriviaQuestion] {
        let live = try await fetchTrivia()
        guard !live.isEmpty else { throw TriviaServiceError.emptyPool }
        return live
    }

    // MARK: - Live fetch

    private func fetchTrivia() async throws -> [TriviaQuestion] {
        guard let url = AppConfig.triviaURL() else {
            throw ContentServiceError.badURL
        }
        return try await fetch([TriviaQuestion].self, from: url)
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
