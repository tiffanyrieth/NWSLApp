//
//  TriviaService.swift
//  NWSLApp
//
//  The app-side client for the LIVE Daily-Trivia question pool — the Fan Zone
//  game's equivalent of `ContentService`. It fetches the proxy's `/trivia` route
//  (the owner-loaded ~500-question pool, served from the Worker's KV) and decodes
//  `[TriviaQuestion]`; the deterministic daily-5 selection stays in
//  `TriviaViewModel`, and the durable streak/accuracy state stays in `TriviaStore`.
//
//  Offline-first, mirroring `ContentService`: the bundled `TriviaQuestionProvider`
//  seed is the fallback whenever the live pipeline is off (`liveContentEnabled`),
//  the route is unreachable, or — unique to trivia — the route comes back EMPTY.
//  (For trivia an empty pool is a failure state, not a valid answer: a quiz with
//  no questions can't be played, so we degrade to the seed rather than show an
//  "out of questions" error. This is the one deliberate deviation from
//  `ContentService`, where an empty list is legitimate.)
//
//  DEBUG `-useSeedContent` forces the seed even when the live pipeline is on
//  (the same escape hatch `ContentService` uses, mirroring `-useESPNDirect`).
//

import Foundation

struct TriviaService {
    var session: URLSession = .shared

    /// The bundled question bank, used as the offline-first fallback (and the only
    /// source while `liveContentEnabled` is false). Injectable for tests/previews.
    var seed = TriviaQuestionProvider()

    /// The full question pool. Live: the proxy `/trivia` route (the owner-loaded
    /// pool from KV). Any failure — disabled pipeline, network error, or an empty
    /// response — degrades to the curated seed so the game is always playable.
    func triviaQuestions() async -> [TriviaQuestion] {
        guard AppConfig.liveContentEnabled, !forceSeed else {
            return await seed.questions()
        }
        do {
            let live = try await fetchTrivia()
            // An empty live pool can't back a quiz — treat it as a miss and fall
            // back to the seed (offline-first). This differs from `ContentService`,
            // where an empty content list is a valid, non-failure answer.
            return live.isEmpty ? await seed.questions() : live
        } catch {
            return await seed.questions()
        }
    }

    // MARK: - Live fetch

    private func fetchTrivia() async throws -> [TriviaQuestion] {
        guard let url = AppConfig.triviaURL() else {
            throw ContentServiceError.badURL
        }
        return try await fetch([TriviaQuestion].self, from: url)
    }

    /// DEBUG escape hatch: `-useSeedContent` in the Run scheme forces the seed even
    /// when the live pipeline is enabled (mirrors `ContentService`).
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
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ContentServiceError.decoding(error)
        }
    }
}
