//
//  SpotlightSchedulingTests.swift
//  NWSLAppTests
//
//  The KHG "new round" nudge is a SCHEDULED (content) notification: fire at a good LOCAL hour, but NEVER
//  before the content is live worldwide, and never at night. NWSL is global (100+ followable national
//  teams, international stars), so a fan in London or Sydney must not be told "new round" before it exists.
//  These lock the timezone behaviour of the pure `spotlightFireDate` seam across the globe.
//
//  A JUNE drop-Monday is used deliberately: in June, LA=PDT(−7), Berlin=CEST(+2), Sydney=AEST(+10), and
//  Auckland=NZST(+12) are all in a stable, unambiguous offset, so the exact-hour assertions don't hinge on
//  a DST changeover.
//

import Foundation
import Testing
@testable import NWSLApp

struct SpotlightSchedulingTests {

    /// A UTC date (midnight), timezone-independent — the kind of UTC Monday `weekStart` produces.
    private func utc(_ s: String) -> Date {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)!
    }

    /// A calendar pinned to a named timezone — the device-timezone seam `spotlightFireDate` takes.
    private func cal(_ id: String) -> Calendar {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone(identifier: id)!
        return c
    }

    private let monday = "2026-06-01"          // a KHG drop Monday (week-offset 12, even)
    private let earlyNow = "2026-05-01"        // well before any computed fire

    private var availability: Date {
        FanZoneCadence.availabilityInstant(for: .knowHerGame, dropMonday: utc(monday))  // Jun 1 10:00 UTC
    }

    // MARK: - The universal invariant + per-zone behaviour

    @Test func usZonesFireAtLocalMondayTenAM() throws {
        // The Americas are west of the 10:00 UTC publish, so their local 10 AM is always AFTER content —
        // the baseline stays exactly Monday 10:00 local (unchanged US behaviour).
        let la = cal("America/Los_Angeles")
        let fire = try #require(NotificationScheduler.spotlightFireDate(
            dropMonday: utc(monday), calendar: la, now: utc(earlyNow)))
        #expect(fire >= availability)                        // never before content is live
        #expect(la.component(.hour, from: fire) == 10)       // 10 AM local
        #expect(la.component(.weekday, from: fire) == 2)     // still Monday (date-label anchor)
    }

    @Test func europeClampsToAvailabilityNotItsEarlierLocalTenAM() throws {
        // London/Berlin's local 10 AM is BEFORE the 10:00 UTC publish, so the nudge clamps FORWARD to the
        // moment content is live (avail + buffer) — the fix for the "~1–2h early" defect.
        let berlin = cal("Europe/Berlin")
        let fire = try #require(NotificationScheduler.spotlightFireDate(
            dropMonday: utc(monday), calendar: berlin, now: utc(earlyNow)))
        #expect(fire == availability.addingTimeInterval(10 * 60))   // == avail + buffer
        let hour = berlin.component(.hour, from: fire)
        #expect(hour >= 10 && hour < 21)                            // daytime, not before 10 AM
    }

    @Test func sydneyFiresSameDayEveningUnderTheCutoff() throws {
        // Sydney (AEST, +10) has content live at ~8 PM local — an evening nudge, same day, under the 9 PM
        // cutoff. The fix for the "~10h early" defect (was firing at their Monday 10 AM, hours early).
        let sydney = cal("Australia/Sydney")
        let fire = try #require(NotificationScheduler.spotlightFireDate(
            dropMonday: utc(monday), calendar: sydney, now: utc(earlyNow)))
        #expect(fire == availability.addingTimeInterval(10 * 60))
        #expect(sydney.component(.hour, from: fire) == 20)          // ~8 PM
        #expect(sydney.component(.weekday, from: fire) == 2)        // still Monday
    }

    @Test func farEastRollsToNextMorningByTheNightGuard() throws {
        // Auckland (NZST, +12) has content live at ~10 PM local — past the 9 PM cutoff — so the night
        // guard rolls it to the next morning's 10 AM rather than pinging at night.
        let auckland = cal("Pacific/Auckland")
        let fire = try #require(NotificationScheduler.spotlightFireDate(
            dropMonday: utc(monday), calendar: auckland, now: utc(earlyNow)))
        #expect(fire >= availability)
        #expect(auckland.component(.hour, from: fire) == 10)        // 10 AM
        #expect(auckland.component(.weekday, from: fire) == 3)      // Tuesday (rolled forward)
    }

    @Test func aPastDropReturnsNil() {
        // Once the fire moment has passed, the drop is skipped (the caller relies on the next one).
        let la = cal("America/Los_Angeles")
        #expect(NotificationScheduler.spotlightFireDate(
            dropMonday: utc(monday), calendar: la, now: utc("2026-07-01")) == nil)
    }

    @Test func copyNamesKnowHerGame() {
        // Trivia gets no nudge; the copy is always Know Her Game.
        #expect(NotificationScheduler.spotlightTitle.contains("Know Her Game"))
        #expect(!NotificationScheduler.spotlightBody.isEmpty)
    }
}
