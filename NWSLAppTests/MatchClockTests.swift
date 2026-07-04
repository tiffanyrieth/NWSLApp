//
//  MatchClockTests.swift
//  NWSLAppTests
//
//  The football-clock helper (Shared/MatchActivityAttributes.swift): whole-minute
//  ticking with broadcast-style stoppage ("45'+2'", "90'+3'") off match-ELAPSED
//  seconds + period. Pure logic, shared by the app cards + the Live Activity widget.
//

import Foundation
import Testing
@testable import NWSLApp

struct MatchClockTests {

    // Helper: minutes → seconds, for readable cases.
    private func min(_ m: Double) -> Double { m * 60 }

    @Test func firstHalfTicksByWholeMinute() {
        // 1-based "current minute": 1' from kickoff, advancing each whole minute.
        #expect(MatchClock.minuteLabel(elapsedSeconds: 0, period: 1) == "1'")
        #expect(MatchClock.minuteLabel(elapsedSeconds: 30, period: 1) == "1'")
        #expect(MatchClock.minuteLabel(elapsedSeconds: min(1), period: 1) == "2'")
        #expect(MatchClock.minuteLabel(elapsedSeconds: min(44), period: 1) == "45'")
    }

    @Test func firstHalfStoppageFoldsPast45() {
        // At 45:00 we're into added time → "45'+1'", then +2, +3…
        #expect(MatchClock.minuteLabel(elapsedSeconds: min(45), period: 1) == "45'+1'")
        #expect(MatchClock.minuteLabel(elapsedSeconds: min(47), period: 1) == "45'+3'")
    }

    @Test func secondHalfUsesContinuousElapsedAnd90Cap() {
        // ESPN's clock is continuous, so H2 elapsed is ~46–90 min → reads "51'", "90'".
        #expect(MatchClock.minuteLabel(elapsedSeconds: min(45), period: 2) == "46'")
        #expect(MatchClock.minuteLabel(elapsedSeconds: min(50), period: 2) == "51'")
        #expect(MatchClock.minuteLabel(elapsedSeconds: min(89), period: 2) == "90'")
    }

    @Test func secondHalfStoppageFoldsPast90() {
        #expect(MatchClock.minuteLabel(elapsedSeconds: min(90), period: 2) == "90'+1'")
        #expect(MatchClock.minuteLabel(elapsedSeconds: min(93), period: 2) == "90'+4'")
    }

    @Test func extraTimeCaps() {
        #expect(MatchClock.regulationCap(period: 3) == 105)
        #expect(MatchClock.regulationCap(period: 4) == 120)
        #expect(MatchClock.minuteLabel(elapsedSeconds: min(105), period: 3) == "105'+1'")
    }

    @Test func unknownPeriodHasNoCap() {
        // No period → don't fold to stoppage; just show the raw minute (fail-soft).
        #expect(MatchClock.regulationCap(period: nil) == nil)
        #expect(MatchClock.minuteLabel(elapsedSeconds: min(100), period: nil) == "101'")
    }
}
