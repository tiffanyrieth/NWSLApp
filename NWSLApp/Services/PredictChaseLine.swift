//
//  PredictChaseLine.swift
//  NWSLApp
//
//  The Predict leaderboard's "chase line" — the gap to the rank directly above you, translated into a
//  GAMEPLAY ACTION rather than a bare stat (owner call, game-feel pass). It replaces the season card's
//  old `nextRungText` ("0.4 behind CapitalKick at #7").
//
//  ⚠️ EACH BOARD SPEAKS ITS OWN TRUE METRIC (owner decision). The ROUND board ranks by that week's raw
//  points, where a correct starter is worth a known, exact number of points — so its chase reads in
//  STARTERS ("1 more correct starter catches …"), the currency the player actually spends. The SEASON
//  board ranks by AVERAGE points per match, where "one more starter" doesn't cleanly translate (it moves
//  the average by an amount that shrinks as you play), so its chase reads in the average gap
//  ("0.4 avg to catch …"). Forcing starters onto the season board would be a fabricated-precise number.
//
//  Pure + deterministic so it unit-tests without a view or the network.
//

import Foundation

enum PredictChaseLine {
    enum Clock { case round, season }

    /// The minimum a caller needs from one leaderboard row. Mapped from the view's `LeaderboardRow`.
    struct Row {
        let rank: Int
        let name: String
        let isYou: Bool
        /// SEASON metric — average points per match. Nil on the round board.
        let avg: Double?
        /// ROUND metric — the week's raw points.
        let points: Int
    }

    /// The chase line, or nil when there's nothing honest to say (you're not in the fetched window, or
    /// there's no neighbour to name — an invented target is worse than no line).
    ///
    /// - You have someone above you → the gap to CATCH them, framed for the board's clock.
    /// - You're #1 → what you're LEADING the next player by.
    static func text(clock: Clock, rows: [Row]) -> String? {
        guard let me = rows.first(where: { $0.isYou }) else { return nil }

        // The player one place above (the closest smaller rank we actually fetched).
        if let above = rows.filter({ !$0.isYou && $0.rank < me.rank }).max(by: { $0.rank < $1.rank }) {
            switch clock {
            case .round:
                // Points → correct starters (each worth `playerPoints`). "catches" = draws level on the
                // current gap; a motivational read of where you stand now, which is the whole point.
                let gap = max(0, above.points - me.points)
                let starters = max(1, Int((Double(gap) / Double(PredictionScore.playerPoints)).rounded(.up)))
                return "\(starters) more correct starter\(starters == 1 ? "" : "s") catches \(above.name) at #\(above.rank)"
            case .season:
                guard let mine = me.avg, let theirs = above.avg, theirs > mine else { return nil }
                return String(format: "%.1f avg to catch %@ at #%d", theirs - mine, above.name, above.rank)
            }
        }

        // Top of the fetched board — name what you're leading the next player by.
        guard let below = rows.filter({ !$0.isYou && $0.rank > me.rank }).min(by: { $0.rank < $1.rank }) else {
            return nil
        }
        switch clock {
        case .round:
            let gap = max(0, me.points - below.points)
            return "Leading \(below.name) by \(gap) pt\(gap == 1 ? "" : "s")"
        case .season:
            guard let mine = me.avg, let theirs = below.avg else { return nil }
            return String(format: "Leading %@ by %.1f avg", below.name, max(0, mine - theirs))
        }
    }
}
