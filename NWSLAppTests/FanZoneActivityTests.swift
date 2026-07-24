//
//  FanZoneActivityTests.swift
//  NWSLAppTests
//
//  The weekly-play ledger behind the "Iron Fan" achievement — consecutive weeks counted back from now,
//  broken by any gap. Injected clock + isolated defaults.
//

import Testing
import Foundation
@testable import NWSLApp

struct FanZoneActivityTests {
    private func suite() -> UserDefaults { UserDefaults(suiteName: "test.activity.\(UUID().uuidString)")! }

    /// A date mid-way through absolute week `ordinal`.
    private func midWeek(_ ordinal: Int) -> Date {
        Date(timeIntervalSince1970: Double(ordinal) * 7 * 86_400 + 3 * 86_400)
    }

    @Test func consecutiveWeeksCountBackFromNow() {
        let d = suite()
        let now = midWeek(100)
        for wk in [100, 99, 98, 97] { FanZoneActivity.recordPlay(now: midWeek(wk), defaults: d) }
        #expect(FanZoneActivity.consecutiveWeeksPlayed(now: now, defaults: d) == 4)
        #expect(Achievement.isIronFan(consecutiveWeeksPlayed:
            FanZoneActivity.consecutiveWeeksPlayed(now: now, defaults: d)))
    }

    @Test func aGapBreaksTheStreak() {
        let d = suite()
        // Played weeks 100 and 98 — the missing 99 breaks the run right after the current week.
        FanZoneActivity.recordPlay(now: midWeek(100), defaults: d)
        FanZoneActivity.recordPlay(now: midWeek(98), defaults: d)
        #expect(FanZoneActivity.consecutiveWeeksPlayed(now: midWeek(100), defaults: d) == 1)
    }

    @Test func notPlayingThisWeekIsZero() {
        let d = suite()
        FanZoneActivity.recordPlay(now: midWeek(99), defaults: d)   // last week only
        #expect(FanZoneActivity.consecutiveWeeksPlayed(now: midWeek(100), defaults: d) == 0)
    }

    @Test func replayingTheSameWeekIsIdempotent() {
        let d = suite()
        FanZoneActivity.recordPlay(now: midWeek(100), defaults: d)
        FanZoneActivity.recordPlay(now: Date(timeIntervalSince1970: 100 * 7 * 86_400 + 5 * 86_400), defaults: d)
        #expect(FanZoneActivity.consecutiveWeeksPlayed(now: midWeek(100), defaults: d) == 1)
    }
}
