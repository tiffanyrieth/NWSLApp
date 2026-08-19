//
//  PredictStreakLine.swift
//  NWSLApp
//
//  The one contextual "you're on a run" line under the username on the Predict hub (game-feel pass).
//  It is FLAVOR: at most one line, shown only when there's something genuinely true to say, never
//  forced. A blank line is the correct state most of the time.
//
//  ⚠️ ONLY HONEST, LOCALLY-KNOWABLE SIGNALS. The inputs are all things the device already holds — the
//  recent scored results, the season high-water mark, and the last-match rank movement the store already
//  persists. We do NOT invent a "climbing for 4 rounds" claim we can't back from stored rank history.
//
//  Pure + deterministic (no `Date()` read inside) so it unit-tests cleanly.
//

import Foundation

enum PredictStreakLine {
    struct Result: Equatable {
        /// An SF Symbol — bolt for a streak, star for a personal best, arrow for climbing.
        let icon: String
        let text: String
    }

    /// One recent scored match, across any followed team. `kickoff` orders them; `starters` = correct
    /// starters called that match.
    struct Match: Equatable {
        let kickoff: Date
        let starters: Int
    }

    /// The best positive per-team rank movement since the user's last scored match (from the store's
    /// persisted delta), with the club's display label for the copy.
    struct Climb: Equatable {
        let delta: Int
        let teamLabel: String
    }

    /// Minimum consecutive rising matches to call it a streak. A pair isn't a run.
    static let streakFloor = 3

    /// Resolve the single most relevant line (priority: personal best → hot streak → climbing), or nil.
    static func resolve(recent: [Match],
                        bestMatchStarters: Int,
                        hasMatchBaseline: Bool,
                        bestClimb: Climb?) -> Result? {
        let ordered = recent.sorted { $0.kickoff < $1.kickoff }

        // 1) Personal best — the most recent match matches the season high AND is the unique high of the
        // recent window (so it reads as "you just set it", not a lingering old peak).
        if hasMatchBaseline, let last = ordered.last, last.starters == bestMatchStarters {
            let othersMax = ordered.dropLast().map(\.starters).max() ?? 0
            if last.starters > othersMax || ordered.count == 1 {
                return Result(icon: "star.fill",
                              text: "New season best: called \(last.starters) of 11 starters")
            }
        }

        // 2) Hot streak — the tail of the window is strictly rising for `streakFloor`+ matches.
        let rising = trailingRisingRun(ordered.map(\.starters))
        if rising >= streakFloor {
            return Result(icon: "bolt.fill", text: "Hot streak: \(rising) matches climbing")
        }

        // 3) Climbing — rank moved up on some board since the last scored match.
        if let climb = bestClimb, climb.delta > 0 {
            return Result(icon: "arrow.up.right",
                          text: "Climbed \(climb.delta) on the \(climb.teamLabel) board")
        }

        return nil
    }

    /// Length of the strictly-increasing run ending at the last element (counts the matches in the run).
    private static func trailingRisingRun(_ values: [Int]) -> Int {
        guard !values.isEmpty else { return 0 }
        var run = 1
        var i = values.count - 1
        while i > 0, values[i] > values[i - 1] {
            run += 1
            i -= 1
        }
        return run
    }
}
