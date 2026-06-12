//
//  XIPrediction.swift
//  NWSLApp
//
//  The LIVE Predict the XI model — Fan Zone game 1 (0.3.9). Replaces the old
//  static `PredictionMatch`/`PredictionQuestion` card seed: instead of four
//  multiple-choice questions with baked answer keys, the user now predicts a real
//  starting XI (11 players), the formation, and the final scoreline for their
//  followed team, scored Mastermind-style against the actual lineup ESPN publishes
//  after the match.
//
//  These are plain value types — no UI, no networking. The two-phase shape is the
//  whole reason this is a model, not a seed: BEFORE a match there is no answer
//  (`PredictionFixture` + the user's `XIPrediction` built from the roster); AFTER
//  it, `ActualResult` (from ESPN `/summary` + the final score) is what
//  `PredictionScoring` grades against. See Reference/Design/games-design-spec.md
//  §"Game 3: Predict the XI" and the 0.3.9 plan.
//

import Foundation

// MARK: - Position group

/// The four position bands a slot/player collapses to. We score "correct
/// position" at this granularity (not exact slot) so a formation mismatch
/// ("you put her at left-back, she played right-back") never costs points — only
/// the band has to match (GK/DEF/MID/FWD).
enum PositionGroup: String, Codable, CaseIterable, Identifiable {
    case gk, def, mid, fwd

    var id: String { rawValue }

    /// Short tracked-caps label for a slot ("GK"/"DEF"/"MID"/"FWD").
    var shortLabel: String {
        switch self {
        case .gk: return "GK"
        case .def: return "DEF"
        case .mid: return "MID"
        case .fwd: return "FWD"
        }
    }

    /// Section title for the roster picker sheet.
    var sectionTitle: String {
        switch self {
        case .gk: return "Goalkeepers"
        case .def: return "Defenders"
        case .mid: return "Midfielders"
        case .fwd: return "Forwards"
        }
    }

    /// Map an ESPN position abbreviation ("G"/"D"/"M"/"F" and the specific
    /// variants like "CB"/"RWB"/"DM"/"AM"/"RW") to one of four bands. Mirrors
    /// FormationPitchView's banding, but collapses DM/AM into MID — we only need
    /// the four scoring groups, not the six display lines. Unknown → MID.
    static func from(abbreviation: String?) -> PositionGroup {
        let base = (abbreviation ?? "").uppercased()
            .split(separator: "-").first.map(String.init) ?? (abbreviation ?? "").uppercased()
        switch base {
        case "G", "GK":
            return .gk
        case "D", "CB", "CD", "RB", "LB", "RCB", "LCB", "WB", "RWB", "LWB", "SW", "FB":
            return .def
        case "F", "CF", "ST", "S", "SS", "W", "RW", "LW", "RF", "LF", "FW":
            return .fwd
        default:
            return .mid   // M, CM, DM, AM, MF, and anything unrecognized
        }
    }

    /// Map an ESPN position *name* ("Goalkeeper"/"Defender"/…) — the field roster
    /// athletes carry — to a band. Falls back to MID for the unexpected.
    static func from(positionName: String?) -> PositionGroup {
        switch (positionName ?? "").lowercased() {
        case let n where n.contains("goal"): return .gk
        case let n where n.contains("defend") || n.contains("back"): return .def
        case let n where n.contains("forward") || n.contains("strik") || n.contains("wing"): return .fwd
        default: return .mid
        }
    }
}

// MARK: - Formation

/// A formation as a parsed set of 11 slots. The raw string ("4-3-3") is the
/// source of truth for both the picker grid and the +5 "correct formation" check.
/// Slot 0 is always the keeper; the outfield rows run defence (row 1) → attack
/// (last row), each slot tagged with its position band.
struct Formation: Identifiable, Equatable {
    let raw: String
    let slots: [Slot]

    var id: String { raw }

    /// One position in the XI: a stable index, its band, and the visual row it
    /// sits on (0 = GK, increasing toward attack).
    struct Slot: Identifiable, Equatable {
        let index: Int
        let group: PositionGroup
        let row: Int
        var id: Int { index }
    }

    /// "4-3-3" → 11 slots. Returns nil unless the digits are 2–5 positive numbers
    /// summing to 10 outfielders (so an unparseable/odd string can't build a grid).
    init?(raw: String) {
        let rowCounts = raw.split(separator: "-").compactMap { Int($0) }
        guard (2...5).contains(rowCounts.count),
              rowCounts.allSatisfy({ $0 > 0 }),
              rowCounts.reduce(0, +) == 10 else { return nil }

        var slots: [Slot] = [Slot(index: 0, group: .gk, row: 0)]
        var index = 1
        let lastRow = rowCounts.count - 1
        for (rowIndex, count) in rowCounts.enumerated() {
            let group: PositionGroup = rowIndex == 0 ? .def : (rowIndex == lastRow ? .fwd : .mid)
            for _ in 0..<count {
                slots.append(Slot(index: index, group: group, row: rowIndex + 1))
                index += 1
            }
        }
        self.raw = raw
        self.slots = slots
    }

    /// The slot at a given index (used by the scorer to read a predicted slot's
    /// band), nil if out of range.
    func slot(at index: Int) -> Slot? { slots.first { $0.index == index } }

    /// Slots grouped into display rows, ATTACK first (top of the grid) → GK last.
    var displayRows: [[Slot]] {
        Dictionary(grouping: slots, by: \.row)
            .sorted { $0.key > $1.key }
            .map { $0.value.sorted { $0.index < $1.index } }
    }

    /// The selectable formations (the common shapes a fan would call). Order is
    /// the picker menu order.
    static let common: [Formation] = [
        "4-3-3", "4-4-2", "4-2-3-1", "3-5-2", "3-4-3", "5-3-2", "4-5-1", "4-1-4-1",
    ].compactMap(Formation.init)

    static let `default` = Formation(raw: "4-3-3")!
}

// MARK: - Fixture (a predictable match)

/// A match the user can predict, built at runtime from the shared MatchStore +
/// the user's follows. Not persisted — it's re-derived each load from live data.
/// `id` (the fixtureID) is the stable key the user's prediction + its score are
/// stored under: one per (event, your team), so following BOTH sides of a match
/// yields two independent predictions.
struct PredictionFixture: Identifiable, Equatable {
    let eventID: String
    let teamAbbreviation: String     // the team whose XI you predict (a followed club)
    let opponentAbbreviation: String
    let isHome: Bool
    let kickoff: Date

    var id: String { Self.fixtureID(eventID: eventID, team: teamAbbreviation) }

    /// Submission closes here — kickoff minus two hours (before the lineup drops).
    var deadline: Date { kickoff.addingTimeInterval(-2 * 3600) }

    /// The Fan Zone visibility window: Predict the XI is "active" (shown on Home
    /// AND playable) only when a followed team has a fixture within 28 days —
    /// otherwise the game goes dark everywhere (no dead links in a long break /
    /// offseason). Both the Home gate and the VM slate use this one horizon.
    static let activeWindow: TimeInterval = 28 * 24 * 3600

    static func fixtureID(eventID: String, team: String) -> String { "\(eventID)-\(team)" }
}

// MARK: - The user's prediction

enum PredictionState: String, Codable {
    case draft       // editable, not yet committed
    case submitted   // locked in — eligible for scoring, no edits
}

/// One saved prediction (persisted in PredictionStore). `slots` maps a formation
/// slot index → the chosen athlete id; a complete XI fills all 11.
struct XIPrediction: Codable, Equatable {
    let fixtureID: String
    let eventID: String
    let teamAbbreviation: String
    var formation: String
    var slots: [Int: String]         // slot index → athlete id
    var homeScoreGuess: Int
    var awayScoreGuess: Int
    var state: PredictionState

    /// All 11 slots filled — the gate on submitting.
    var isComplete: Bool { slots.count == 11 }

    /// The athlete ids picked (for de-duping the roster sheet against slots
    /// already filled).
    var pickedAthleteIDs: Set<String> { Set(slots.values) }

    init(fixtureID: String, eventID: String, teamAbbreviation: String,
         formation: String = Formation.default.raw,
         slots: [Int: String] = [:],
         homeScoreGuess: Int = 0, awayScoreGuess: Int = 0,
         state: PredictionState = .draft) {
        self.fixtureID = fixtureID
        self.eventID = eventID
        self.teamAbbreviation = teamAbbreviation
        self.formation = formation
        self.slots = slots
        self.homeScoreGuess = homeScoreGuess
        self.awayScoreGuess = awayScoreGuess
        self.state = state
    }
}

// MARK: - Actual result (the answer key, from ESPN /summary + final score)

/// What actually happened, used only to score a submitted prediction. Built from
/// the match `/summary` (starting XI + formation) and the scoreboard `Event`
/// (final score).
struct ActualResult: Equatable {
    let formation: String?
    let starters: [Starter]
    let homeScore: Int
    let awayScore: Int

    struct Starter: Equatable {
        let athleteID: String
        let group: PositionGroup
    }

    var starterIDs: Set<String> { Set(starters.map(\.athleteID)) }

    func group(forAthlete id: String) -> PositionGroup? {
        starters.first { $0.athleteID == id }?.group
    }

    /// Build the answer key for the side you predicted from a decoded `/summary`
    /// (lineup + formation) plus the final score from the scoreboard `Event`.
    /// Returns nil unless that side's full XI is present — we never score against a
    /// partial lineup (ESPN occasionally posts an incomplete one).
    static func make(from summary: MatchSummary, isHome: Bool,
                     homeScore: Int, awayScore: Int) -> ActualResult? {
        guard let roster = isHome ? summary.homeRoster : summary.awayRoster else { return nil }
        let starters = roster.starters.compactMap { player -> Starter? in
            guard let id = player.athlete?.id else { return nil }
            return Starter(athleteID: id, group: .from(abbreviation: player.position?.abbreviation))
        }
        guard starters.count == 11 else { return nil }
        return ActualResult(formation: roster.formation, starters: starters,
                            homeScore: homeScore, awayScore: awayScore)
    }
}

// MARK: - Score breakdown

/// The graded result of one prediction. Persisted so a scored match never needs a
/// re-fetch, and rendered category-by-category on the results card.
struct PredictionScore: Codable, Equatable {
    var correctPlayers: Int        // count of XI picks who actually started (≤11)
    var correctPositions: Int      // of those, how many sat in the right band
    var formationCorrect: Bool
    var exactScoreline: Bool       // stacks with resultCorrect (per owner)
    var resultCorrect: Bool        // W/D/L right, even if the score was wrong
    var perfectXI: Bool            // all 11 correct

    // Per-category points (the spec's fixed weights).
    var playersPoints: Int { correctPlayers * 3 }
    var positionsPoints: Int { correctPositions * 2 }
    var formationPoints: Int { formationCorrect ? 5 : 0 }
    var scorelinePoints: Int { exactScoreline ? 10 : 0 }
    var resultPoints: Int { resultCorrect ? 3 : 0 }
    var perfectPoints: Int { perfectXI ? 15 : 0 }

    var total: Int {
        playersPoints + positionsPoints + formationPoints
            + scorelinePoints + resultPoints + perfectPoints
    }

    static let zero = PredictionScore(correctPlayers: 0, correctPositions: 0,
                                      formationCorrect: false, exactScoreline: false,
                                      resultCorrect: false, perfectXI: false)
}
