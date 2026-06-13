//
//  GameCenterIDsTests.swift
//  NWSLAppTests
//
//  Pins the Game Center identifier constants and the pure cross-game score math.
//  The IDs MUST byte-match the App Store Connect records or every submission
//  silently no-ops — this test is the guard that the app and the ASC checklist
//  never drift apart.
//

import Testing
@testable import NWSLApp

struct GameCenterIDsTests {
    private let prefix = "com.tiffanyrieth.nwslapp.NWSLApp"

    @Test func leaderboardIDsAreExact() {
        #expect(GameCenterID.Leaderboard.triviaStreak        == "\(prefix).leaderboard.trivia.streak")
        #expect(GameCenterID.Leaderboard.predictSeasonPoints == "\(prefix).leaderboard.predict.seasonpoints")
        #expect(GameCenterID.Leaderboard.bracketTotalPoints  == "\(prefix).leaderboard.bracket.totalpoints")
        #expect(GameCenterID.Leaderboard.superfanTotal       == "\(prefix).leaderboard.superfan.total")
        #expect(GameCenterID.Leaderboard.all.count == 4)
    }

    @Test func achievementIDsAreExact() {
        #expect(GameCenterID.Achievement.firstPrediction  == "\(prefix).achievement.first_prediction")
        #expect(GameCenterID.Achievement.triviaPerfectDay == "\(prefix).achievement.trivia_perfect_day")
        #expect(GameCenterID.Achievement.triviaStreak7    == "\(prefix).achievement.trivia_streak_7")
        #expect(GameCenterID.Achievement.triviaStreak30   == "\(prefix).achievement.trivia_streak_30")
        #expect(GameCenterID.Achievement.bracketRoundWon  == "\(prefix).achievement.bracket_round_won")
        #expect(GameCenterID.Achievement.playedAllThree   == "\(prefix).achievement.played_all_three")
        #expect(GameCenterID.Achievement.all.count == 6)
    }

    @Test func allIDsAreUniqueAndPrefixed() {
        let ids = GameCenterID.Leaderboard.all + GameCenterID.Achievement.all
        #expect(Set(ids).count == ids.count)                 // no duplicates
        #expect(ids.allSatisfy { $0.hasPrefix(prefix) })     // all namespaced
    }

    @Test func superfanTotalSumsTheThreeGames() {
        #expect(GameCenterScores.superfanTotal(triviaTotalCorrect: 40, predictSeasonPoints: 84, bracketPoints: 12) == 136)
        #expect(GameCenterScores.superfanTotal(triviaTotalCorrect: 0, predictSeasonPoints: 0, bracketPoints: 0) == 0)
    }

    @Test func playedAllThreeNeedsEveryGame() {
        #expect(GameCenterScores.playedAllThree(playedTrivia: true, hasPredicted: true, playedBracket: true))
        #expect(!GameCenterScores.playedAllThree(playedTrivia: true, hasPredicted: true, playedBracket: false))
        #expect(!GameCenterScores.playedAllThree(playedTrivia: false, hasPredicted: true, playedBracket: true))
        #expect(!GameCenterScores.playedAllThree(playedTrivia: true, hasPredicted: false, playedBracket: true))
        #expect(!GameCenterScores.playedAllThree(playedTrivia: false, hasPredicted: false, playedBracket: false))
    }
}
