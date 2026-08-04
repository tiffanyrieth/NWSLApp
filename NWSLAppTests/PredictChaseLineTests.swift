//
//  PredictChaseLineTests.swift
//  NWSLAppTests
//
//  The leaderboard "chase line" translates the gap to the rank above you into a gameplay action. It
//  speaks each board's true metric: the ROUND board in correct starters (points ÷ playerPoints), the
//  SEASON board in the average gap. These tests pin that translation + the #1 "leading by" case.
//

import Foundation
import Testing
@testable import NWSLApp

struct PredictChaseLineTests {

    private func row(_ rank: Int, _ name: String, isYou: Bool = false, avg: Double? = nil, points: Int = 0) -> PredictChaseLine.Row {
        PredictChaseLine.Row(rank: rank, name: name, isYou: isYou, avg: avg, points: points)
    }

    @Test func roundBoardFramesGapInStarters() {
        // You're #8 on 40 pts; #7 is on 46 — a 6-point gap = 2 correct starters (3 pts each).
        let rows = [row(7, "CapitalKick", points: 46), row(8, "You", isYou: true, points: 40)]
        #expect(PredictChaseLine.text(clock: .round, rows: rows)
                == "2 more correct starters catches CapitalKick at #7")
    }

    @Test func roundBoardRoundsUpAndSingularizes() {
        // A 1-point gap still rounds up to a single starter, phrased singular.
        let rows = [row(6, "ReignMaker", points: 31), row(7, "You", isYou: true, points: 30)]
        #expect(PredictChaseLine.text(clock: .round, rows: rows)
                == "1 more correct starter catches ReignMaker at #6")
    }

    @Test func seasonBoardFramesGapInAverage() {
        let rows = [row(7, "CapitalKick", avg: 6.8), row(8, "You", isYou: true, avg: 6.4)]
        #expect(PredictChaseLine.text(clock: .season, rows: rows)
                == "0.4 avg to catch CapitalKick at #7")
    }

    @Test func topOfBoardLeads() {
        let seasonRows = [row(1, "You", isYou: true, avg: 7.2), row(2, "Runner", avg: 6.9)]
        #expect(PredictChaseLine.text(clock: .season, rows: seasonRows)
                == "Leading Runner by 0.3 avg")
        let roundRows = [row(1, "You", isYou: true, points: 40), row(2, "Runner", points: 34)]
        #expect(PredictChaseLine.text(clock: .round, rows: roundRows)
                == "Leading Runner by 6 pts")
    }

    @Test func noYouRowGivesNoLine() {
        #expect(PredictChaseLine.text(clock: .season, rows: [row(1, "Someone", avg: 5)]) == nil)
    }

    @Test func aloneOnBoardGivesNoLine() {
        // Just you, nobody above or below — nothing honest to chase.
        #expect(PredictChaseLine.text(clock: .season, rows: [row(1, "You", isYou: true, avg: 5)]) == nil)
    }
}
