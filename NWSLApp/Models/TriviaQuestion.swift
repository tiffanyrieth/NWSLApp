//
//  TriviaQuestion.swift
//  NWSLApp
//
//  One Daily-Trivia question — Home's Module 3 "Play", game 1 (per
//  Reference/Design/games-design-spec.md). Flat, view-friendly, and Codable-
//  shaped like PlayerSpotlight / FeedItem, so it decodes straight from the live
//  proxy `/trivia` route (the owner-loaded KV pool). No model/view change needed.
//
//  Each question is multiple-choice with exactly four options; `correctIndex`
//  points into `options`. `category` and `difficulty` let the backend balance the
//  daily mix (and the UI label a question) — they ride along on each question and
//  surface as a small chip on the card.
//

import Foundation

struct TriviaQuestion: Identifiable, Codable, Equatable {
    let id: String
    /// The prompt, e.g. "Which club has won the most NWSL Championships?".
    let question: String
    /// Exactly four answer choices. Index into this is the player's pick.
    let options: [String]
    /// The index into `options` that is correct (0–3).
    let correctIndex: Int
    let category: Category
    let difficulty: Difficulty

    /// The correct option string, for the results recap.
    var correctAnswer: String { options[correctIndex] }

    /// Spec §Question categories — used to balance/label the daily mix.
    enum Category: String, Codable {
        case leagueHistory      // "which team has won the most championships?"
        case playerFacts        // "first overall pick in the 2024 draft?"
        case venues             // "which stadium has the largest capacity?"
        case rules              // "how many substitutions per match?"
        case records            // "most assists in a season?"
        case teamHistory        // "which team relocated from another city?"

        /// Short human label for the on-card chip.
        var label: String {
            switch self {
            case .leagueHistory: return "League History"
            case .playerFacts:   return "Player Facts"
            case .venues:        return "Stadiums"
            case .rules:         return "Rules"
            case .records:       return "Records"
            case .teamHistory:   return "Team History"
            }
        }
    }

    enum Difficulty: String, Codable {
        case easy, medium, hard
    }
}
