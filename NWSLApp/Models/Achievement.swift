//
//  Achievement.swift
//  NWSLApp
//
//  The Fan Zone achievements — the Superfan "Your Best Moments" (Competitive Redesign, PR4). Nine badges
//  earned across the four games, DETECTED CLIENT-SIDE at game completion (no Supabase Edge Functions — the
//  minimal-dependency stance) and written to `user_achievements` (award is idempotent via the table's
//  unique constraint). This file is the pure model: the badge metadata + the threshold checks, all
//  SwiftUI-free-detection so every rule is unit-testable (AchievementTests). Presentation (symbol/color)
//  uses the shared DS tokens.
//
//  ⚠️ UPSET RULE (Dark Horse / Upset Royalty): the handoff defines an upset as "pick won with <40% / <30%
//  community vote" — but Bracket Battle is a MAJORITY-WINS 2-way bracket, so a winner ALWAYS has >50% of
//  the vote; a <40% winner is impossible. So detection uses the SEED gap instead: an upset is when the
//  community advanced the lower-seeded (underdog) entrant and the user picked it. Documented for the owner
//  to confirm/adjust the intended rule.
//

import SwiftUI

enum Achievement: String, CaseIterable, Identifiable {
    case perfectRound  = "perfect_round"   // 10/10 on a Know Her Game quiz
    case darkHorse     = "dark_horse"      // 3+ upset picks in one Bracket round
    case streakMaster  = "streak_master"   // 5+ consecutive Trivia rounds
    case lineupOracle  = "lineup_oracle"   // 9+ of 11 starters in one Predict match
    case firstBlood    = "first_blood"     // complete your first Fan Zone game
    case wellRounded   = "well_rounded"    // earn points in all four games in a season
    case upsetRoyalty  = "upset_royalty"   // pick a BIG upset in Bracket ("Upset King/Queen")
    case knowItAll     = "know_it_all"     // score 8+ on 5 different Know Her Game players
    case ironFan       = "iron_fan"        // play a Fan Zone game every week for 4 consecutive weeks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .perfectRound: return "Perfect Round"
        case .darkHorse:    return "Dark Horse"
        case .streakMaster: return "Streak Master"
        case .lineupOracle: return "Lineup Oracle"
        case .firstBlood:   return "First Blood"
        case .wellRounded:  return "Well-Rounded"
        case .upsetRoyalty: return "Upset Royalty"
        case .knowItAll:    return "Know It All"
        case .ironFan:      return "Iron Fan"
        }
    }

    /// The card copy when no per-earn `metadata` detail is stored (the flavor detail — "10/10 on Sandy
    /// MacIver" — overrides this at the call site).
    var defaultDescription: String {
        switch self {
        case .perfectRound: return "A perfect Know Her Game round."
        case .darkHorse:    return "Called 3 upsets in a single Bracket round."
        case .streakMaster: return "Five NWSL Trivia rounds in a row."
        case .lineupOracle: return "Nailed 9+ of 11 starters in one match."
        case .firstBlood:   return "Played your first Fan Zone game."
        case .wellRounded:  return "Scored in all four games this season."
        case .upsetRoyalty: return "Backed a big Bracket underdog — and won."
        case .knowItAll:    return "Aced 5 different Know Her Game players."
        case .ironFan:      return "Played every week for four weeks straight."
        }
    }

    /// SF Symbol (never emoji in game UI).
    var symbol: String {
        switch self {
        case .perfectRound: return "target"
        case .darkHorse:    return "star.fill"
        case .streakMaster: return "bolt.fill"
        case .lineupOracle: return "scope"
        case .firstBlood:   return "trophy.fill"
        case .wellRounded:  return "square.grid.2x2.fill"
        case .upsetRoyalty: return "crown.fill"
        case .knowItAll:    return "brain.head.profile"
        case .ironFan:      return "shield.fill"
        }
    }

    /// Badge accent — the source game's color, or gold/teal for the cross-game ones (shared DS tokens).
    var color: Color {
        switch self {
        case .perfectRound, .knowItAll: return .dsGameSpotlight   // Know Her Game gold/amber
        case .darkHorse:                return .dsGameBracket      // Bracket teal
        case .streakMaster:             return .dsGameTrivia       // Trivia indigo
        case .lineupOracle:             return .dsGamePredict      // Predict pink
        case .firstBlood, .ironFan:     return .dsGameBracket      // teal (cross-game)
        case .wellRounded, .upsetRoyalty: return .dsWarning        // gold
        }
    }
}

// MARK: - Pure detection (thresholds + checks — no I/O, unit-tested)

extension Achievement {
    static let darkHorseUpsetsRequired = 3
    static let streakMasterRounds = 5
    static let lineupOracleCorrect = 9
    static let knowItAllPlayers = 5
    static let knowItAllScore = 8
    static let wellRoundedGames = 4
    static let ironFanWeeks = 4
    static let bigUpsetSeedGap = 16

    static func isPerfectRound(correct: Int, outOf total: Int) -> Bool { total > 0 && correct == total }
    static func isLineupOracle(correctPlayers: Int) -> Bool { correctPlayers >= lineupOracleCorrect }
    static func isStreakMaster(triviaRoundStreak: Int) -> Bool { triviaRoundStreak >= streakMasterRounds }
    static func isDarkHorse(upsetWins: Int) -> Bool { upsetWins >= darkHorseUpsetsRequired }
    static func isKnowItAll(playersScored8Plus: Int) -> Bool { playersScored8Plus >= knowItAllPlayers }
    static func isWellRounded(gamesWithSeasonPoints: Int) -> Bool { gamesWithSeasonPoints >= wellRoundedGames }
    static func isIronFan(consecutiveWeeksPlayed: Int) -> Bool { consecutiveWeeksPlayed >= ironFanWeeks }

    /// An upset the user CALLED: the community advanced the lower-seeded (underdog) entrant and the user
    /// picked it. (Seed-based — see the ⚠️ note at the top; "<40% vote" is impossible for a majority winner.)
    /// Higher seed NUMBER = lower seed = underdog.
    static func isUpsetWin(pickedWinner: Bool, winnerSeed: Int?, loserSeed: Int?) -> Bool {
        guard pickedWinner, let w = winnerSeed, let l = loserSeed else { return false }
        return w > l
    }

    /// A BIG upset (Upset Royalty): the underdog the user called was seeded far below its opponent.
    static func isBigUpsetWin(pickedWinner: Bool, winnerSeed: Int?, loserSeed: Int?) -> Bool {
        guard pickedWinner, let w = winnerSeed, let l = loserSeed else { return false }
        return w - l >= bigUpsetSeedGap
    }
}
