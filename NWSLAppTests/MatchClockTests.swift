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


// MARK: - Monotonic tick anchors (the stoppage-time freeze fix, 2026-07-05)

/// ESPN FREEZES `status.clock` at 45:00/90:00 through stoppage time. These lock the MatchStore
/// rule that keeps the FIRST-SEEN anchor while a match's clock is frozen — without it, the ~30s
/// poll re-anchored the local tick and pinned the display at 45'+1' for all of stoppage.
struct TickAnchorTests {
    private func liveEvent(id: String = "e1", clock: Double, period: Int, state: String = "in") -> Event {
        Event(id: id, name: nil, shortName: nil, date: nil,
              status: EventStatus(period: period,
                                  type: StatusType(state: state, description: nil, shortDetail: nil),
                                  clock: clock),
              competitions: nil)
    }

    @Test func frozenClockKeepsTheOriginalAnchor() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let first = MatchStore.reconciledTickAnchors(previous: [:], events: [liveEvent(clock: 2700, period: 1)], at: t0)
        #expect(first["e1"]?.date == t0)

        // 30s later ESPN still reports 2700 (stoppage): the anchor must NOT move, so
        // elapsed = 2700 + (now − anchor) keeps climbing into +2'…+11'.
        let second = MatchStore.reconciledTickAnchors(previous: first, events: [liveEvent(clock: 2700, period: 1)], at: t0.addingTimeInterval(30))
        #expect(second["e1"]?.date == t0)

        // Integration: 130s after t0 with the kept anchor → 45'+3' (was pinned at +1 before the fix).
        let elapsed = 2700 + t0.addingTimeInterval(130).timeIntervalSince(second["e1"]!.date)
        #expect(MatchClock.minuteLabel(elapsedSeconds: elapsed, period: 1) == "45'+3'")
    }

    @Test func advancingClockReAnchors() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let first = MatchStore.reconciledTickAnchors(previous: [:], events: [liveEvent(clock: 1500, period: 1)], at: t0)
        let t1 = t0.addingTimeInterval(30)
        let second = MatchStore.reconciledTickAnchors(previous: first, events: [liveEvent(clock: 1530, period: 1)], at: t1)
        #expect(second["e1"]?.date == t1)      // clock advanced → fresh anchor (drift correction)
        #expect(second["e1"]?.clock == 1530)
    }

    @Test func periodChangeReAnchors() {
        // The halftime pause legitimately breaks continuity: same clock value, new period → re-anchor.
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let first = MatchStore.reconciledTickAnchors(previous: [:], events: [liveEvent(clock: 2700, period: 1)], at: t0)
        let t1 = t0.addingTimeInterval(900)
        let second = MatchStore.reconciledTickAnchors(previous: first, events: [liveEvent(clock: 2700, period: 2)], at: t1)
        #expect(second["e1"]?.date == t1)
        #expect(second["e1"]?.period == 2)
    }

    @Test func nonLiveMatchesDropOut() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let first = MatchStore.reconciledTickAnchors(previous: [:], events: [liveEvent(clock: 2700, period: 1)], at: t0)
        let ended = MatchStore.reconciledTickAnchors(previous: first, events: [liveEvent(clock: 5400, period: 2, state: "post")], at: t0.addingTimeInterval(60))
        #expect(ended["e1"] == nil)
    }
}
