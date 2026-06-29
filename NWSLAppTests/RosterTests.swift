//
//  RosterTests.swift
//  NWSLAppTests
//
//  Decode-only tests for RosterResponse → ClubSquad, focused on the proxy's
//  last-known-good resilience layer: when the proxy serves a cached roster (ESPN
//  came back implausibly small) it injects a top-level `proxyCachedAsOf`, which the
//  app surfaces as ClubSquad.cachedAsOf to drive the honest "Roster as of …"
//  indicator. A live roster has no marker → cachedAsOf is nil.
//

import Foundation
import Testing
@testable import NWSLApp

struct RosterTests {

    private func decode(_ json: String) throws -> ClubSquad {
        try JSONDecoder().decode(RosterResponse.self, from: Data(json.utf8)).squad
    }

    @Test func liveRosterHasNoCachedMarker() throws {
        let json = """
        { "team": { "color": "C8102E", "standingSummary": "1st in NWSL", "recordSummary": "10-2-1" },
          "athletes": [
            { "id": "1", "fullName": "A. Keeper", "jersey": "1", "position": { "displayName": "Goalkeeper", "abbreviation": "G" } },
            { "id": "2", "fullName": "B. Striker", "jersey": "9", "position": { "displayName": "Forward", "abbreviation": "F" } }
          ] }
        """
        let squad = try decode(json)
        #expect(squad.athletes.count == 2)
        #expect(squad.cachedAsOf == nil)          // live → no indicator
        #expect(squad.colorHex == "C8102E")
    }

    @Test func cachedRosterParsesProxyCachedAsOf() throws {
        let json = """
        { "proxyCachedAsOf": "2026-06-29T16:53:41.341Z",
          "team": { "color": "202121", "standingSummary": "12th in NWSL", "recordSummary": "4-1-6" },
          "athletes": [
            { "id": "174410", "fullName": "Sydney Leroux", "jersey": "2", "position": { "displayName": "Forward", "abbreviation": "F" } },
            { "id": "acfc-ary-borges", "fullName": "Ary Borges", "jersey": "8", "position": { "displayName": "Midfielder", "abbreviation": "M" } }
          ] }
        """
        let squad = try decode(json)
        #expect(squad.athletes.count == 2)

        // The ISO8601-with-fractional-seconds marker parses to a real Date → the
        // "Roster as of …" indicator shows. Assert the calendar date (UTC), not a raw
        // epoch literal.
        let cached = try #require(squad.cachedAsOf)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day], from: cached)
        #expect(c.year == 2026 && c.month == 6 && c.day == 29)

        // Synthetic ids (new 2026 signings in the seed) survive decode like real ESPN ids.
        #expect(squad.athletes.contains { $0.id == "acfc-ary-borges" })
    }
}
