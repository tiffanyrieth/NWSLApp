//
//  CommunityResultsLineTests.swift
//  NWSLAppTests
//
//  The one community line under each question on the shared results panel (Know Her Game + NWSL
//  Trivia): "47 out of 50 fans nailed this". Pure string logic, so it's tested here rather than in
//  the sim.
//
//  ⚠️ These tests exist to PIN the raw-count format. It read "94% · 47 of 50 fans nailed this" until
//  2026-07-29; the leading percentage was cut because `correctCount` is by definition the fans who
//  picked the correct option, so it duplicated that option's own bar percentage on every question.
//  A future change that re-adds a percentage here should fail these and be a deliberate decision,
//  not a drive-by "improvement".
//

import Foundation
import Testing
@testable import NWSLApp

struct CommunityResultsLineTests {

    @Test func countIsRawWithNoLeadingPercentage() {
        let line = CommunityResultsView.nailedLine(correct: 47, total: 50)
        #expect(line == "47 out of 50 fans nailed this")
        #expect(!line.contains("%"))
    }

    @Test func aLoneResponderReadsAsOneFanNotOneFans() {
        // The first player to finish a round sees this, so the singular has to be right — it's the
        // honest "1 fan played" hook, and a grammar slip there undercuts it.
        #expect(CommunityResultsView.nailedLine(correct: 1, total: 1) == "1 out of 1 fan nailed this")
        #expect(CommunityResultsView.nailedLine(correct: 0, total: 1) == "0 out of 1 fan nailed this")
    }

    @Test func noResponsesYetIsHonestRatherThanAZeroRatio() {
        // A revealed round nobody has answered: "0 out of 0 fans nailed this" reads like a result.
        // This is the honest-empty rule — say there's no data, don't render a hollow statistic.
        #expect(CommunityResultsView.nailedLine(correct: 0, total: 0) == "No answers yet")
    }

    @Test func nobodyGotItAndEverybodyGotItBothRead() {
        #expect(CommunityResultsView.nailedLine(correct: 0, total: 59) == "0 out of 59 fans nailed this")
        #expect(CommunityResultsView.nailedLine(correct: 59, total: 59) == "59 out of 59 fans nailed this")
    }
}
