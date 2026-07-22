//
//  QuizResultsService.swift
//  NWSLApp
//
//  The community-results data client, SHARED by NWSL Trivia + Know Her Game (docs §11b) —
//  the NYT-style "how everyone did" screen that REPLACES a competitive leaderboard for the
//  quiz games. Two halves, matching the cost-safe backend split:
//
//   • WRITE — on completion the app upserts its per-question answers to Supabase
//     `quiz_answers` (RLS owner-only; PK (user_id, game, edition_key, question_id) → a
//     replay can't inflate the counts). Uses the supabase-swift SDK, like the *_scores
//     services. Signed-in only (the caller gates behind FanZoneGate, so it always is).
//
//   • READ — the aggregate DISTRIBUTION comes from the PROXY (`GET /quiz-results`), which
//     computes it once from Supabase (as service_role) and serves it from its edge cache.
//     The app NEVER aggregates Supabase directly (the Swifties-tour cost lesson). A read
//     failure returns nil and the UI shows an honest "couldn't load", never fabricated %.
//

import Foundation
import Supabase

/// One answered question, ready to persist to the community aggregate.
struct QuizAnswer {
    let questionID: String
    let selectedIndex: Int
    let isCorrect: Bool
}

/// The decoded community distribution for one edition (the proxy `/quiz-results` payload).
/// When `revealed` is false (a still-open Trivia day) the aggregate fields are ABSENT —
/// the payload is just `{game, editionKey, revealed:false}`. A CUSTOM decoder is required:
/// Swift's synthesized `Decodable` IGNORES a property's default value and throws
/// `keyNotFound` on a missing non-optional key, so the synthesized version failed to decode
/// the sparse payload → the "how everyone did" panel showed a false "couldn't load" every
/// day a fan played Trivia (looked broken). `decodeIfPresent` + fallbacks fixes it and also
/// hardens the shared Know Her path against any future sparse payload.
struct QuizResults: Decodable {
    let revealed: Bool
    var responders: Int = 0
    var showPercent: Bool = false
    var avgCorrect: Double?
    var questions: [Question] = []

    struct Question: Decodable, Identifiable {
        let questionId: String
        let total: Int
        let correctCount: Int
        /// selected-option index (as a string key) → how many fans picked it.
        let optionCounts: [String: Int]

        var id: String { questionId }
        func count(forOption index: Int) -> Int { optionCounts[String(index)] ?? 0 }
    }

    private enum CodingKeys: String, CodingKey {
        case revealed, responders, showPercent, avgCorrect, questions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        revealed = try c.decode(Bool.self, forKey: .revealed)   // the one field always present
        responders = try c.decodeIfPresent(Int.self, forKey: .responders) ?? 0
        showPercent = try c.decodeIfPresent(Bool.self, forKey: .showPercent) ?? false
        avgCorrect = try c.decodeIfPresent(Double.self, forKey: .avgCorrect)
        questions = try c.decodeIfPresent([Question].self, forKey: .questions) ?? []
    }
}

struct QuizResultsService {
    var session: URLSession = .shared
    private var client: SupabaseClient { SupabaseManager.client }

    // MARK: - Write (Supabase)

    /// Persist this edition's answers. Best-effort + idempotent (upsert on the PK): a failure
    /// leaves the local score intact and is flagged via telemetry (NO SILENT FAILURES), not
    /// surfaced to the user (the personal result still shows).
    func upsert(game: String, editionKey: String, answers: [QuizAnswer],
                userID: UUID, season: String) async {
        guard !answers.isEmpty else { return }
        let rows = answers.map {
            AnswerUpsert(user_id: userID, game: game, edition_key: editionKey,
                        question_id: $0.questionID, selected_index: $0.selectedIndex,
                        is_correct: $0.isCorrect, season: season)
        }
        do {
            try await client
                .from("quiz_answers")
                .upsert(rows, onConflict: "user_id,game,edition_key,question_id")
                .execute()
        } catch {
            await MainActor.run {
                Diagnostics.shared.record(.apiFailure, "quiz upsert \(game): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Read (proxy edge cache)

    /// The community distribution for one edition, from the proxy. Returns nil on any failure
    /// (the caller shows an honest "couldn't load community results").
    func results(game: String, edition: String) async -> QuizResults? {
        guard let url = AppConfig.quizResultsURL(game: game, edition: edition) else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                await MainActor.run {
                    Diagnostics.shared.record(.apiFailure, "quiz results \(game): HTTP \(http.statusCode)")
                }
                return nil
            }
            return try JSONDecoder().decode(QuizResults.self, from: data)
        } catch {
            await MainActor.run {
                Diagnostics.shared.record(.apiFailure, "quiz results \(game): \(error.localizedDescription)")
            }
            return nil
        }
    }
}

// snake_case to match the Postgres columns exactly (PostgREST maps 1:1).
private struct AnswerUpsert: Encodable {
    let user_id: UUID
    let game: String
    let edition_key: String
    let question_id: String
    let selected_index: Int
    let is_correct: Bool
    let season: String
}
