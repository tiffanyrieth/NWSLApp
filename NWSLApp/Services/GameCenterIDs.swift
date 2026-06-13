//
//  GameCenterIDs.swift
//  NWSLApp
//
//  Game Center (GameKit) identifier constants + the pure cross-game score helpers,
//  deliberately FREE of `import GameKit` so they're unit-testable on their own and
//  so the one place these strings live is plain Swift, not buried in the manager.
//
//  These IDs must byte-match the leaderboard/achievement records created in App
//  Store Connect, or every submission silently no-ops (the #1 Game Center failure
//  mode). `GameCenterIDsTests` pins them; the App Store Connect checklist mirrors
//  them exactly. They're additive on top of the real Supabase leaderboards — Game
//  Center is the native cross-player ranking skin, the in-app boards are the data.
//

import Foundation

/// Reverse-DNS Game Center identifiers, namespaced under the bundle id.
enum GameCenterID {
    /// The four leaderboards (3 per-game + a combined Superfan total).
    enum Leaderboard {
        static let triviaStreak        = "com.tiffanyrieth.nwslapp.NWSLApp.leaderboard.trivia.streak"
        static let predictSeasonPoints = "com.tiffanyrieth.nwslapp.NWSLApp.leaderboard.predict.seasonpoints"
        static let bracketTotalPoints  = "com.tiffanyrieth.nwslapp.NWSLApp.leaderboard.bracket.totalpoints"
        static let superfanTotal       = "com.tiffanyrieth.nwslapp.NWSLApp.leaderboard.superfan.total"

        static let all = [triviaStreak, predictSeasonPoints, bracketTotalPoints, superfanTotal]
    }

    /// The starter achievement set.
    enum Achievement {
        static let firstPrediction   = "com.tiffanyrieth.nwslapp.NWSLApp.achievement.first_prediction"
        static let triviaPerfectDay  = "com.tiffanyrieth.nwslapp.NWSLApp.achievement.trivia_perfect_day"
        static let triviaStreak7     = "com.tiffanyrieth.nwslapp.NWSLApp.achievement.trivia_streak_7"
        static let triviaStreak30    = "com.tiffanyrieth.nwslapp.NWSLApp.achievement.trivia_streak_30"
        static let bracketRoundWon   = "com.tiffanyrieth.nwslapp.NWSLApp.achievement.bracket_round_won"
        static let playedAllThree    = "com.tiffanyrieth.nwslapp.NWSLApp.achievement.played_all_three"

        static let all = [firstPrediction, triviaPerfectDay, triviaStreak7,
                          triviaStreak30, bracketRoundWon, playedAllThree]
    }
}

/// Pure cross-game score math (no GameKit, no stores) so it's directly testable.
enum GameCenterScores {
    /// The combined "Superfan" total. Trivia contributes lifetime correct answers
    /// (cumulative + points-like), so the three terms sum as comparable quantities —
    /// the dedicated Trivia board still ranks by best STREAK.
    static func superfanTotal(triviaTotalCorrect: Int, predictSeasonPoints: Int, bracketPoints: Int) -> Int {
        triviaTotalCorrect + predictSeasonPoints + bracketPoints
    }

    /// "Played All 3 Games" — true only once the user has engaged with every game.
    static func playedAllThree(playedTrivia: Bool, hasPredicted: Bool, playedBracket: Bool) -> Bool {
        playedTrivia && hasPredicted && playedBracket
    }
}
