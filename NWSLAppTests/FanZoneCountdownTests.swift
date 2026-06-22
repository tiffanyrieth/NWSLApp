//
//  FanZoneCountdownTests.swift
//  NWSLAppTests
//
//  Pins `compactCountdown(to:from:)` — the pure formatter behind the Fan Zone
//  countdown pills ("2d 14h left", "New in 6h"). It's `now`-injected so the boundaries
//  (days / hours / minutes / sub-minute / past) are deterministic to assert.
//

import Testing
import Foundation
@testable import NWSLApp

struct FanZoneCountdownTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func ahead(_ seconds: Int) -> Date { now.addingTimeInterval(TimeInterval(seconds)) }

    @Test func daysAndHours() {
        // 2 days, 14 hours, 30 minutes → days drop minutes, keep hours.
        let target = ahead(2 * 86_400 + 14 * 3600 + 30 * 60)
        #expect(compactCountdown(to: target, from: now) == "2d 14h")
    }

    @Test func wholeDaysOnly() {
        // Exactly 3 days → no trailing "0h".
        #expect(compactCountdown(to: ahead(3 * 86_400), from: now) == "3d")
    }

    @Test func hoursOnly() {
        // 18h 12m, under a day → hours only (matches the design's "18h left").
        #expect(compactCountdown(to: ahead(18 * 3600 + 12 * 60), from: now) == "18h")
    }

    @Test func minutesOnly() {
        #expect(compactCountdown(to: ahead(47 * 60), from: now) == "47m")
    }

    @Test func subMinute() {
        #expect(compactCountdown(to: ahead(30), from: now) == "<1m")
    }

    @Test func pastOrNowReturnsNil() {
        // A stale deadline shows no pill rather than "0m".
        #expect(compactCountdown(to: now, from: now) == nil)
        #expect(compactCountdown(to: ahead(-3600), from: now) == nil)
    }
}
