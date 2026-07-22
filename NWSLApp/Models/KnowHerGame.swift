//
//  KnowHerGame.swift
//  NWSLApp
//
//  The content model for Know Her Game — the weekly "how well do you know this
//  player?" quiz that replaces the passive Player Spotlight (docs/know-her-game.md).
//  Decodes the proxy's `GET /knowher?teams=` pool document (KV-backed, owner-loaded
//  in manual mode). The shape mirrors the proxy's `src/knowher.ts` validator 1:1 —
//  keep the two in sync.
//
//  Online-only, like TriviaQuestion: there is no bundled seed. The service throws on
//  an empty/failed load and the game hides; the app never fabricates a player.
//

import Foundation

/// One quiz question — multiple-choice (4 options) or true/false (2). `correctIndex`
/// points into `options`. `revealFact` is the "learn" payoff shown on the result screen.
struct KnowHerQuestion: Identifiable, Codable, Equatable {
    let id: String
    let category: Category
    let prompt: String
    let options: [String]
    let correctIndex: Int
    let revealFact: String?

    var correctAnswer: String { options.indices.contains(correctIndex) ? options[correctIndex] : "" }
    var isTrueFalse: Bool { category == .trueOrFalse }

    /// The four question lenses (docs §7). Labels surface on the question screen.
    enum Category: String, Codable {
        case herGame        // stats / on-the-pitch
        case herStory       // career / identity / origin
        case herWorld       // personality / life beyond soccer (within the guardrail)
        case trueOrFalse    // hyper-specific true/false

        var label: String {
            switch self {
            case .herGame:     return "Her game"
            case .herStory:    return "Her story"
            case .herWorld:    return "Her world"
            case .trueOrFalse: return "True or false"
            }
        }
    }
}

/// One featured player for the week (one per followed team). The headshot is resolved
/// on-device from `espnAthleteId` via `HeadshotStore` (no URL travels in the pool).
struct KnowHerPlayer: Identifiable, Codable, Equatable {
    let teamAbbreviation: String
    let espnAthleteId: String
    /// Numeric ESPN team id, stamped server-side at publish. The app doesn't use it (headshots resolve
    /// from `espnAthleteId`); it rides the pool so the match-watcher can target this team's followers for
    /// the biweekly KHG push. Optional so older pool payloads still decode.
    let espnTeamId: String?
    let playerName: String
    let jerseyNumber: Int
    let position: String
    let tagline: String
    let questions: [KnowHerQuestion]

    /// Stable identity for lists/ForEach — one player per team per week.
    var id: String { espnAthleteId }

    /// The per-edition key that keys played state (KnowHerGameStore) and the community
    /// results aggregate (`quiz_answers.edition_key`): "{weekKey}-{team}-{athleteId}".
    func editionKey(weekKey: String) -> String {
        "\(weekKey)-\(teamAbbreviation.uppercased())-\(espnAthleteId)"
    }
}

/// The whole weekly pool document served by the proxy, already filtered to the
/// requested teams. `weekKey` (e.g. "2026-W27") stamps the Mon–Sun window.
struct KnowHerPool: Codable, Equatable {
    let weekKey: String
    let season: Int
    /// 1-based edition index this season, stamped by the proxy at publish — the picker's "Round N".
    /// Optional so older pool payloads (and previews/tests) still decode.
    let round: Int?
    let players: [KnowHerPlayer]
}
