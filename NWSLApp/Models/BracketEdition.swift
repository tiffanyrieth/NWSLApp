//
//  BracketEdition.swift
//  NWSLApp
//
//  Bracket Battle — the LIVE community-voting tournament (Fan Zone game 2, 0.3.9).
//  Replaces the old ⚠️seed "one GK per club, 16-team, simulated-vote" edition with
//  the real concept: a themed edition pulls a LARGE pool of qualifying players from
//  ESPN (64 → 32 first-round matchups → 6 rounds), and the COMMUNITY votes each
//  round on who advances. You don't pick who *should* win — you predict who the
//  crowd will advance, scored on real Supabase vote tallies (see BracketService).
//
//  These are plain value types — no UI, no networking. A live edition is assembled
//  by BracketService from Supabase rows (the global edition + matchups + the
//  community tally once a round closes); the model is just the shape the views and
//  the scorer read. `teamAbbreviation` is the crest/name join key the rest of the
//  app uses (ESPN gives no stable competitor id).
//
//  Design: Reference/Design/games-design-spec.md §"Game 2: Bracket Battle" + the
//  Claude Design 5-screen reference (Bracket Battle Reference.html) + the 0.3.9 plan.
//  Scope tonight is the clean power-of-two pool (64, no byes); byes for odd pools
//  are a documented follow-up.
//

import Foundation

// MARK: - Round

/// A tournament round, keyed by how many ENTRANTS contest it (64 → Round of 64).
/// Points ESCALATE by round — later picks are harder to predict, so they're worth
/// more (owner-set weights). The set generalises to any power-of-two pool: a
/// 32-player edition just starts at `.roundOf32`.
enum BracketRound: Int, Codable, CaseIterable, Comparable {
    case roundOf64 = 64
    case roundOf32 = 32
    case roundOf16 = 16
    case quarterfinal = 8
    case semifinal = 4
    case final = 2

    /// Matchups in this round (entrants ÷ 2): Rd of 64 = 32, … Final = 1.
    var matchupCount: Int { rawValue / 2 }

    /// Points for ONE correct pick in this round (escalating).
    var points: Int {
        switch self {
        case .roundOf64: return 5
        case .roundOf32: return 8
        case .roundOf16: return 12
        case .quarterfinal: return 18
        case .semifinal: return 25
        case .final: return 40
        }
    }

    /// Full title for headers ("Round of 64", "Quarterfinals", "Final").
    var title: String {
        switch self {
        case .roundOf64: return "Round of 64"
        case .roundOf32: return "Round of 32"
        case .roundOf16: return "Round of 16"
        case .quarterfinal: return "Quarterfinals"
        case .semifinal: return "Semifinals"
        case .final: return "Final"
        }
    }

    /// Compact label for pills/overview ("Rd of 64", "QF", "SF", "Final").
    var shortLabel: String {
        switch self {
        case .roundOf64: return "Rd of 64"
        case .roundOf32: return "Rd of 32"
        case .roundOf16: return "Rd of 16"
        case .quarterfinal: return "QF"
        case .semifinal: return "SF"
        case .final: return "Final"
        }
    }

    /// Earlier rounds (more entrants) sort first.
    static func < (lhs: BracketRound, rhs: BracketRound) -> Bool { lhs.rawValue > rhs.rawValue }

    /// The ordered rounds for a pool of `entrants` (a power of two, ≤ 64): e.g.
    /// 64 → [.roundOf64 … .final]; 32 → [.roundOf32 … .final].
    static func rounds(forEntrants entrants: Int) -> [BracketRound] {
        allCases.filter { $0.rawValue <= entrants }.sorted()
    }
}

// MARK: - Theme type

/// How an edition's player pool is chosen. Both rotate in the live schedule.
enum BracketThemeType: String, Codable {
    /// Position/stat-filtered from ESPN — "Best Forward" (goals), "Best GK" (saves).
    case statsSeeded
    /// ALL rostered players eligible; a personality/culture theme (Haiku-generated)
    /// — "best celebration", "who wins a staring contest". No stat filter.
    case creative
}

// MARK: - Entrant

/// One player in an edition's pool. `id` is the ESPN athlete id (the stable key a
/// vote references); the dot shows jersey number + team monogram (no headshots).
struct BracketEntrant: Identifiable, Codable, Equatable {
    let id: String
    let playerName: String
    let jerseyNumber: Int?
    /// Join key → club crest + accent colour + name.
    let teamAbbreviation: String
}

// MARK: - Matchup

/// One head-to-head in a round. `communityWinnerID` + `splitAPercent` are nil until
/// the round closes and the real vote tally resolves it (then both populate).
struct BracketMatchup: Identifiable, Codable, Equatable {
    let id: String
    let round: BracketRound
    let slot: Int
    let entrantA: BracketEntrant
    let entrantB: BracketEntrant

    /// Set once the round closes: the entrant the community advanced.
    var communityWinnerID: String?
    /// A's share of the vote, 0–100 (B's is 100 − this). Nil until closed.
    var splitAPercent: Int?

    var isResolved: Bool { communityWinnerID != nil }

    func entrant(_ id: String) -> BracketEntrant? {
        if entrantA.id == id { return entrantA }
        if entrantB.id == id { return entrantB }
        return nil
    }

    static func matchupID(editionID: String, round: BracketRound, slot: Int) -> String {
        "\(editionID)-r\(round.rawValue)-s\(slot)"
    }
}

// MARK: - Edition

/// A themed tournament. `matchups` is flat (each carries its round) so it stays
/// trivially Codable for the offline-first local cache; completed + the current
/// round are populated, future rounds fill in as the bracket advances.
struct BracketEdition: Identifiable, Codable, Equatable {
    let id: String
    /// Tracked-caps eyebrow over the title ("TOP FORWARD").
    let themeLabel: String
    /// Display title ("Best Forward · 2026").
    let title: String
    /// Hero emoji ("⚽").
    let emoji: String
    let type: BracketThemeType
    /// Seed order, strongest first; count is a power of two (64 tonight).
    let entrants: [BracketEntrant]
    /// The round currently open for voting.
    let currentRound: BracketRound
    /// When the current round opened / closes (drives the countdown + the gate).
    let roundOpenedAt: Date?
    let roundClosesAt: Date?
    /// Total fans who've entered this edition (for the "N fans are already in" line).
    let fanCount: Int
    /// All known matchups across rounds (flat).
    let matchups: [BracketMatchup]

    /// The rounds this edition runs, in order (derived from the pool size).
    var rounds: [BracketRound] { BracketRound.rounds(forEntrants: entrants.count) }

    /// Matchups in a round, in slot order.
    func matchups(in round: BracketRound) -> [BracketMatchup] {
        matchups.filter { $0.round == round }.sorted { $0.slot < $1.slot }
    }

    /// Status of a round relative to the one currently open.
    enum RoundStatus { case complete, active, upcoming }
    func status(of round: BracketRound) -> RoundStatus {
        if round == currentRound { return .active }
        return round < currentRound ? .complete : .upcoming   // earlier rounds sort first
    }
}
