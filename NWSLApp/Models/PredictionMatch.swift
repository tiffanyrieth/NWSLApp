//
//  PredictionMatch.swift
//  NWSLApp
//
//  Predict the XI — Home's Module 3 "Play", game 3 (per Reference/Design/
//  games-design-spec.md §"Game 3: Predict the XI"). Before a match, the user
//  predicts a few key elements — the formation, the starting keeper, the captain,
//  and the first goal scorer — each worth a different point value. Predictions
//  lock at kickoff; once the match is settled, picks are scored against the result.
//
//  Flat, view-friendly, and Codable-shaped like TriviaQuestion / BracketEdition,
//  so today's TEMP static seed (PredictionMatchProvider) can later be swapped for
//  a real matchday/lineup backend with no model or view change. `homeAbbreviation`
//  / `awayAbbreviation` are the join keys the view uses to resolve club crests +
//  names — the same abbreviation-join the rest of the app uses (ESPN gives no
//  stable competitor id).
//
//  Kickoff is modelled as an OFFSET from "now," not an absolute date: a demo seed
//  with fixed dates would drift into the past and leave nothing open to predict.
//  Offsets keep the demo honest — some matches are always settled (past) and at
//  least one is always open (future) whenever the app runs. The ViewModel resolves
//  the offset against an injectable clock; whether a match is open or settled is
//  derived there, never stored.
//
//  The result (the answer key — correct option per question + the final score) is
//  carried on the seed but only REVEALED once a match is settled. That's a demo
//  convenience standing in for a real result feed; the view gates on settled state
//  so an open match never spoils its own answers.
//

import Foundation

/// One prediction category, with its difficulty-scaled point value (spec §"each
/// question has a point value based on difficulty"). The hardest to call — the
/// first goal scorer — pays the most.
enum PredictionCategory: String, Codable, CaseIterable {
    case formation
    case startingGK
    case captain
    case firstScorer

    var title: String {
        switch self {
        case .formation: return "Formation"
        case .startingGK: return "Starting GK"
        case .captain: return "Captain"
        case .firstScorer: return "First Goal Scorer"
        }
    }

    /// Points awarded for a correct pick — the spec's fixed difficulty weighting.
    var points: Int {
        switch self {
        case .formation: return 2
        case .startingGK: return 1
        case .captain: return 2
        case .firstScorer: return 3
        }
    }

    /// An SF Symbol that reads at a glance in the question header.
    var icon: String {
        switch self {
        case .formation: return "square.grid.3x3.fill"
        case .startingGK: return "hand.raised.fill"
        case .captain: return "star.circle.fill"
        case .firstScorer: return "soccerball"
        }
    }
}

/// One answer choice for a question — a formation string, a keeper, a captain, or
/// a candidate scorer. `detail` is an optional secondary line (e.g. the club for a
/// cross-team scorer list, where options come from both sides).
struct PredictionOption: Identifiable, Codable, Equatable {
    let id: String
    let label: String
    let detail: String?

    init(id: String, label: String, detail: String? = nil) {
        self.id = id
        self.label = label
        self.detail = detail
    }
}

/// One prediction within a match — its category (which fixes the point value and
/// icon), a natural-language prompt, the options to choose among, and the answer
/// key. `correctOptionID` is only surfaced by the view once the match is settled.
struct PredictionQuestion: Identifiable, Codable, Equatable {
    let id: String
    let category: PredictionCategory
    /// e.g. "Spirit's formation" or "First goal scorer."
    let prompt: String
    let options: [PredictionOption]
    /// The id of the correct option (the result). Revealed only when settled.
    let correctOptionID: String

    var points: Int { category.points }

    func option(_ id: String?) -> PredictionOption? {
        guard let id else { return nil }
        return options.first { $0.id == id }
    }

    var correctOption: PredictionOption? { option(correctOptionID) }
}

/// A single seed match the user can predict. Kickoff is an offset in hours from
/// "now" (see file header); the final score is the settled result shown alongside
/// the per-question review.
struct PredictionMatch: Identifiable, Codable, Equatable {
    let id: String
    /// Join keys → club crest + name (mirrors the rest of the app).
    let homeAbbreviation: String
    let awayAbbreviation: String
    /// Hours from now until kickoff. Negative = already kicked off (settled in the
    /// demo); positive = upcoming (open for predictions).
    let kickoffOffsetHours: Double
    let questions: [PredictionQuestion]
    /// The settled final score (shown once the match is past kickoff).
    let homeScore: Int
    let awayScore: Int

    /// Total points on offer across every question — the most a match can score.
    var pointsAvailable: Int { questions.reduce(0) { $0 + $1.points } }
}
