//
//  AchievementTests.swift
//  NWSLAppTests
//
//  The pure achievement detection rules (thresholds + the seed-based upset classifier). No I/O.
//

import Testing
@testable import NWSLApp

struct AchievementTests {

    @Test func perfectRoundNeedsEveryQuestion() {
        #expect(Achievement.isPerfectRound(correct: 10, outOf: 10))
        #expect(!Achievement.isPerfectRound(correct: 9, outOf: 10))
        #expect(!Achievement.isPerfectRound(correct: 0, outOf: 0))   // no round played ≠ perfect
    }

    @Test func lineupOracleNeedsNineOfEleven() {
        #expect(Achievement.isLineupOracle(correctPlayers: 9))
        #expect(Achievement.isLineupOracle(correctPlayers: 11))
        #expect(!Achievement.isLineupOracle(correctPlayers: 8))
    }

    @Test func streakMasterNeedsFiveRounds() {
        #expect(Achievement.isStreakMaster(triviaRoundStreak: 5))
        #expect(Achievement.isStreakMaster(triviaRoundStreak: 12))
        #expect(!Achievement.isStreakMaster(triviaRoundStreak: 4))
    }

    @Test func darkHorseNeedsThreeUpsets() {
        #expect(Achievement.isDarkHorse(upsetWins: 3))
        #expect(!Achievement.isDarkHorse(upsetWins: 2))
    }

    @Test func knowItAllNeedsFivePlayers() {
        #expect(Achievement.isKnowItAll(playersScored8Plus: 5))
        #expect(!Achievement.isKnowItAll(playersScored8Plus: 4))
    }

    @Test func wellRoundedNeedsAllFourGames() {
        #expect(Achievement.isWellRounded(gamesWithSeasonPoints: 4))
        #expect(!Achievement.isWellRounded(gamesWithSeasonPoints: 3))
    }

    @Test func ironFanNeedsFourConsecutiveWeeks() {
        #expect(Achievement.isIronFan(consecutiveWeeksPlayed: 4))
        #expect(Achievement.isIronFan(consecutiveWeeksPlayed: 7))
        #expect(!Achievement.isIronFan(consecutiveWeeksPlayed: 3))
    }

    // Upset = the community advanced the lower-seeded (underdog) entrant AND the user picked it.
    // Higher seed NUMBER = lower seed = underdog. (Seed-based, since a <40% majority winner is impossible.)
    @Test func upsetWinNeedsCorrectPickOfTheUnderdog() {
        #expect(Achievement.isUpsetWin(pickedWinner: true, winnerSeed: 30, loserSeed: 3))   // #30 beat #3
        #expect(!Achievement.isUpsetWin(pickedWinner: true, winnerSeed: 3, loserSeed: 30))  // favorite won — not an upset
        #expect(!Achievement.isUpsetWin(pickedWinner: false, winnerSeed: 30, loserSeed: 3)) // didn't call it
        #expect(!Achievement.isUpsetWin(pickedWinner: true, winnerSeed: nil, loserSeed: 3)) // no seed data → no false award
    }

    @Test func bigUpsetNeedsAWideSeedGap() {
        #expect(Achievement.isBigUpsetWin(pickedWinner: true, winnerSeed: 40, loserSeed: 1))   // gap 39
        #expect(!Achievement.isBigUpsetWin(pickedWinner: true, winnerSeed: 10, loserSeed: 1))  // gap 9 < 16
    }
}
