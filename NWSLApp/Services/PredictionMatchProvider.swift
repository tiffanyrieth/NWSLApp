//
//  PredictionMatchProvider.swift
//  NWSLApp
//
//  ⚠️ TEMP / SCAFFOLDING — curated static seed for Home's Module 3 "Play",
//  game 3 (Predict the XI), per Reference/Design/games-design-spec.md.
//
//  WHAT: three sample matches — two already SETTLED (kickoff in the past, with a
//  final score + an answer key for every question) and one OPEN (kickoff in the
//  near future, nothing revealed yet) so the demo always shows both the prediction
//  UI and the results-review screen. Each match carries four questions — formation
//  (2 pts), starting GK (1 pt), captain (2 pts), first goal scorer (3 pts). Also
//  provides a simulated leaderboard of sample usernames the user is ranked against.
//
//  WHY: the spec wants Predict the XI real and playable for a concept demo without
//  a backend — "pre-populate 2-3 sample matches with questions and results … local
//  scoring, simulated leaderboard." Kickoff is an OFFSET from now (not a date) so
//  the open match never drifts into the past (see PredictionMatch's header).
//
//  ACCURACY: matchups, rosters, and answer keys are an illustrative 2026 snapshot
//  gathered by research, leaning on DURABLE names (the researched keeper list is
//  shared with the Bracket seed) over volatile current-season specifics. The
//  settled "results" are invented for the demo. Treat as curated demo content to be
//  editorially re-verified, not a live source of truth.
//
//  WHEN REMOVED: replace `matches()` with a real fixtures + lineup feed (ESPN
//  summaries or the planned proxy) returning the same `PredictionMatch`, and
//  `leaderboardOpponents()` with real standings once multi-user scoring exists (the
//  leaderboard needs the server — spec §Leaderboards). The async signature already
//  fits a network source.
//

import Foundation

struct PredictionMatchProvider {
    func matches() async -> [PredictionMatch] { Self.seed }

    /// Sample opponents for the simulated leaderboard — fixed season-point totals
    /// the user (whose points grow as settled matches are scored) is ranked among.
    /// Replaced by real standings when a scoring backend exists.
    func leaderboardOpponents() -> [(name: String, points: Int)] { Self.opponents }

    // MARK: - Builders

    private static func formationQuestion(_ match: String, team: String, correct: String,
                                          others: [String]) -> PredictionQuestion {
        // The correct formation first, then the rest; the view shuffles for display
        // only if it wants to — order here is not meaningful to scoring.
        let all = [correct] + others
        let options = all.map { PredictionOption(id: "\(match)-form-\($0)", label: $0) }
        return PredictionQuestion(
            id: "\(match)-formation",
            category: .formation,
            prompt: "\(team) formation",
            options: options,
            correctOptionID: "\(match)-form-\(correct)"
        )
    }

    private static func pickQuestion(_ match: String, slug: String, category: PredictionCategory,
                                     prompt: String, options: [(id: String, label: String, detail: String?)],
                                     correct: String) -> PredictionQuestion {
        PredictionQuestion(
            id: "\(match)-\(slug)",
            category: category,
            prompt: prompt,
            options: options.map { PredictionOption(id: "\(match)-\(slug)-\($0.id)", label: $0.label, detail: $0.detail) },
            correctOptionID: "\(match)-\(slug)-\(correct)"
        )
    }

    // MARK: - Seed

    // Two settled (negative offset) + one open (positive offset). The open match's
    // answer keys exist but are never revealed by the view while it's upcoming.
    private static let seed: [PredictionMatch] = [washingtonPortland, kansasCityOrlando, sanDiegoAngelCity]

    // SETTLED ~5 days ago — Washington Spirit 2–1 Portland Thorns.
    private static let washingtonPortland = PredictionMatch(
        id: "was-por",
        homeAbbreviation: "WAS",
        awayAbbreviation: "POR",
        kickoffOffsetHours: -120,
        questions: [
            formationQuestion("was-por", team: "Spirit", correct: "4-3-3",
                              others: ["4-4-2", "3-5-2", "4-2-3-1"]),
            pickQuestion("was-por", slug: "gk", category: .startingGK,
                         prompt: "Spirit starting GK",
                         options: [("kingsbury", "Aubrey Kingsbury", "Washington Spirit"),
                                   ("cappelletti", "Mackenzie Cappelletti", "Washington Spirit")],
                         correct: "kingsbury"),
            pickQuestion("was-por", slug: "captain", category: .captain,
                         prompt: "Spirit captain",
                         options: [("sullivan", "Andi Sullivan", "Washington Spirit"),
                                   ("rodman", "Trinity Rodman", "Washington Spirit"),
                                   ("mckeown", "Tara McKeown", "Washington Spirit")],
                         correct: "sullivan"),
            pickQuestion("was-por", slug: "scorer", category: .firstScorer,
                         prompt: "First goal scorer",
                         options: [("rodman", "Trinity Rodman", "Washington Spirit"),
                                   ("hatch", "Ashley Hatch", "Washington Spirit"),
                                   ("moultrie", "Olivia Moultrie", "Portland Thorns"),
                                   ("weaver", "Morgan Weaver", "Portland Thorns")],
                         correct: "rodman"),
        ],
        homeScore: 2,
        awayScore: 1
    )

    // SETTLED ~2 days ago — Kansas City Current 3–1 Orlando Pride.
    private static let kansasCityOrlando = PredictionMatch(
        id: "kc-orl",
        homeAbbreviation: "KC",
        awayAbbreviation: "ORL",
        kickoffOffsetHours: -45,
        questions: [
            formationQuestion("kc-orl", team: "Current", correct: "4-3-3",
                              others: ["4-4-2", "3-4-3", "4-2-3-1"]),
            pickQuestion("kc-orl", slug: "gk", category: .startingGK,
                         prompt: "Current starting GK",
                         options: [("franch", "Adrianna Franch", "Kansas City Current"),
                                   ("lorena", "Lorena", "Kansas City Current")],
                         correct: "franch"),
            pickQuestion("kc-orl", slug: "captain", category: .captain,
                         prompt: "Current captain",
                         options: [("labonta", "Lo'eau LaBonta", "Kansas City Current"),
                                   ("debinha", "Debinha", "Kansas City Current"),
                                   ("chawinga", "Temwa Chawinga", "Kansas City Current")],
                         correct: "labonta"),
            pickQuestion("kc-orl", slug: "scorer", category: .firstScorer,
                         prompt: "First goal scorer",
                         options: [("chawinga", "Temwa Chawinga", "Kansas City Current"),
                                   ("debinha", "Debinha", "Kansas City Current"),
                                   ("banda", "Barbra Banda", "Orlando Pride"),
                                   ("marta", "Marta", "Orlando Pride")],
                         correct: "chawinga"),
        ],
        homeScore: 3,
        awayScore: 1
    )

    // OPEN ~1.5 days out — San Diego Wave vs Angel City. Answer keys exist for
    // scoring once it settles, but the view never reveals them while it's upcoming.
    private static let sanDiegoAngelCity = PredictionMatch(
        id: "sd-la",
        homeAbbreviation: "SD",
        awayAbbreviation: "LA",
        kickoffOffsetHours: 33,
        questions: [
            formationQuestion("sd-la", team: "Wave", correct: "4-3-3",
                              others: ["4-4-2", "3-5-2", "4-2-3-1"]),
            pickQuestion("sd-la", slug: "gk", category: .startingGK,
                         prompt: "Wave starting GK",
                         options: [("sheridan", "Kailen Sheridan", "San Diego Wave"),
                                   ("haracic", "DiDi Haračić", "San Diego Wave")],
                         correct: "sheridan"),
            pickQuestion("sd-la", slug: "captain", category: .captain,
                         prompt: "Wave captain",
                         options: [("sheridan", "Kailen Sheridan", "San Diego Wave"),
                                   ("mcnabb", "Kristen McNabb", "San Diego Wave"),
                                   ("doniak", "Amirah Ali", "San Diego Wave")],
                         correct: "sheridan"),
            pickQuestion("sd-la", slug: "scorer", category: .firstScorer,
                         prompt: "First goal scorer",
                         options: [("cascarino", "Delphine Cascarino", "San Diego Wave"),
                                   ("shaw", "María Sánchez", "San Diego Wave"),
                                   ("thompson", "Alyssa Thompson", "Angel City"),
                                   ("leroux", "Sydney Leroux", "Angel City")],
                         correct: "cascarino"),
        ],
        homeScore: 0,
        awayScore: 0
    )

    // Soccer-fan-flavoured handles + fixed season totals spanning a believable
    // range, so the user climbs the board as settled matches score.
    private static let opponents: [(name: String, points: Int)] = [
        ("xiwhisperer", 22),
        ("lineup_lucy", 19),
        ("formationfanatic", 17),
        ("captain_calls", 15),
        ("gk_guru", 13),
        ("firstgoalfran", 11),
        ("subzero_sub", 9),
        ("benchmob", 7),
        ("predict_pat", 5),
        ("coinflip_kim", 3),
        ("rookie_riley", 1),
    ]
}
