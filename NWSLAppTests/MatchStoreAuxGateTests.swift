//
//  MatchStoreAuxGateTests.swift
//  NWSLAppTests
//
//  The windowed-refresh aux-feed gate (Part D of the 2026-07-16 polling fix): the live tick
//  re-fetches an auxiliary feed (NT / Champions Cup / Challenge Cup) ONLY when the loaded season
//  shows one of its fixtures with a kickoff within ±36h of now. Locks: per-competition detection,
//  the far-away suppression that IS the saving, the fail-open on an unparseable date (a bad date
//  must never silently starve a feed), and the always-fetched NWSL spine not tripping any gate.
//

import Foundation
import Testing
@testable import NWSLApp

struct MatchStoreAuxGateTests {

    private let now = Date(timeIntervalSince1970: 1_784_246_400)   // fixed reference instant

    /// ESPN's wire format for Event.date ("…T17:00Z", seconds-less) at an offset from `now`.
    private func espnDate(hoursFromNow: Double) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: now.addingTimeInterval(hoursFromNow * 3600))
    }

    private func match(_ competition: CompetitionType, hoursFromNow: Double?) -> ScheduledMatch {
        let date = hoursFromNow.map { espnDate(hoursFromNow: $0) }
        return ScheduledMatch(event: Event(id: UUID().uuidString, date: date), competition: competition)
    }

    @Test func nearFixturesEnableTheirOwnFeedOnly() {
        let gate = MatchStore.auxFeedsWorthPolling(
            loaded: [match(.international("WAFCON"), hoursFromNow: 2)], now: now)
        #expect(gate.nt)
        #expect(!gate.championsCup)
        #expect(!gate.challengeCup)
    }

    @Test func eachCompetitionMapsToItsGate() {
        let gate = MatchStore.auxFeedsWorthPolling(
            loaded: [
                match(.concacafChampionsCup, hoursFromNow: -3),   // played earlier today → still near
                match(.challengeCup, hoursFromNow: 20),
            ], now: now)
        #expect(!gate.nt)
        #expect(gate.championsCup)
        #expect(gate.challengeCup)
    }

    /// The whole point: a season full of far-away aux fixtures polls NOTHING extra on a live tick.
    @Test func farFixturesSuppressAuxFeeds() {
        let gate = MatchStore.auxFeedsWorthPolling(
            loaded: [
                match(.international("Friendly"), hoursFromNow: 24 * 14),   // two weeks out
                match(.challengeCup, hoursFromNow: -24 * 30),               // a month ago
                match(.concacafChampionsCup, hoursFromNow: 37),             // just past the edge
            ], now: now)
        #expect(!gate.nt)
        #expect(!gate.championsCup)
        #expect(!gate.challengeCup)
    }

    @Test func boundaryInsideWindowCounts() {
        let gate = MatchStore.auxFeedsWorthPolling(
            loaded: [match(.international("Friendly"), hoursFromNow: 35.5)], now: now)
        #expect(gate.nt)
    }

    /// NO SILENT FAILURES: an unparseable/missing kickoff fails OPEN — the feed keeps polling.
    @Test func missingDateFailsOpen() {
        let gate = MatchStore.auxFeedsWorthPolling(
            loaded: [match(.challengeCup, hoursFromNow: nil)], now: now)
        #expect(gate.challengeCup)
    }

    /// NWSL fixtures never trip an aux gate (the NWSL board is fetched unconditionally).
    @Test func nwslFixturesTripNothing() {
        let gate = MatchStore.auxFeedsWorthPolling(
            loaded: [match(.nwsl, hoursFromNow: 1)], now: now)
        #expect(!gate.nt)
        #expect(!gate.championsCup)
        #expect(!gate.challengeCup)
    }

    @Test func emptySeasonPollsNothingExtra() {
        let gate = MatchStore.auxFeedsWorthPolling(loaded: [], now: now)
        #expect(!gate.nt && !gate.championsCup && !gate.challengeCup)
    }
}
