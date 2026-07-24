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

    // Upset = the user CALLED a winner the crowd advanced by a ≤10-point margin (winner's share ≤55%).
    // Vote-margin, not seed — a <40% majority winner is impossible in a 2-way bracket (owner ruling 7/24).
    @Test func upsetWinNeedsANarrowMarginAndACorrectCall() {
        #expect(Achievement.isUpsetWin(pickedWinner: true, winnerPercent: 52))   // 52–48 nail-biter you called
        #expect(Achievement.isUpsetWin(pickedWinner: true, winnerPercent: 55))   // exactly at the ceiling
        #expect(!Achievement.isUpsetWin(pickedWinner: true, winnerPercent: 56))  // 56–44 → comfortable, not an upset
        #expect(!Achievement.isUpsetWin(pickedWinner: true, winnerPercent: 70))  // runaway
        #expect(!Achievement.isUpsetWin(pickedWinner: false, winnerPercent: 52)) // didn't call it
        #expect(!Achievement.isUpsetWin(pickedWinner: true, winnerPercent: nil)) // no tally yet → no false award
    }
}
