//
//  RecentFormTests.swift
//  NWSLAppTests
//
//  Pins the pure last-5 form derivation that feeds the Standings "Last 5" column
//  (RecentForm). The standings table has no recent-results from ESPN, so this
//  logic — completed matches → ordered W/D/L per club — must be correct.
//

import Foundation
import Testing
@testable import NWSLApp

struct RecentFormTests {

    /// Build a scoreboard Event for one match. `state` "post" == final.
    private func match(
        _ home: String, _ homeScore: Int?,
        _ away: String, _ awayScore: Int?,
        state: String = "post",
        date: String
    ) -> Event {
        Event(
            id: "\(home)-\(away)-\(date)",
            name: nil,
            shortName: nil,
            date: date,
            status: EventStatus(displayClock: nil, period: nil,
                                type: StatusType(state: state, description: nil, shortDetail: nil)),
            competitions: [
                Competition(
                    competitors: [
                        Competitor(homeAway: "home", score: homeScore.map(String.init),
                                   team: Team(displayName: nil, abbreviation: home, shortDisplayName: nil, logo: nil)),
                        Competitor(homeAway: "away", score: awayScore.map(String.init),
                                   team: Team(displayName: nil, abbreviation: away, shortDisplayName: nil, logo: nil)),
                    ],
                    venue: nil, broadcasts: nil
                )
            ]
        )
    }

    /// Compact W/D/L string for a results sequence, so expectations read clearly
    /// without needing Equatable on the shared MatchResult enum.
    private func letters(_ results: [MatchResult]?) -> String {
        (results ?? []).map {
            switch $0 {
            case .win: return "W"
            case .draw: return "D"
            case .loss: return "L"
            }
        }.joined()
    }

    @Test func classifiesWinDrawLossFromBothSides() {
        // POR 2–1 SEA: POR win (home), SEA loss (away).
        // KC 0–0 BAY: both draw.
        let season = [
            match("POR", 2, "SEA", 1, date: "2026-03-01T17:00Z"),
            match("KC", 0, "BAY", 0, date: "2026-03-02T17:00Z"),
        ]
        let form = RecentForm.lastFiveByAbbreviation(in: season)
        #expect(letters(form["POR"]) == "W")
        #expect(letters(form["SEA"]) == "L")
        #expect(letters(form["KC"]) == "D")
        #expect(letters(form["BAY"]) == "D")
    }

    @Test func ordersOldestToNewestRegardlessOfInputOrder() {
        // Fed out of order; POR's results should read by kickoff: W (Mar 1), L (Mar 8), D (Mar 15).
        let season = [
            match("POR", 1, "KC", 1, date: "2026-03-15T17:00Z"),   // draw, newest
            match("POR", 3, "BAY", 0, date: "2026-03-01T17:00Z"),  // win, oldest
            match("SEA", 2, "POR", 0, date: "2026-03-08T17:00Z"),  // POR loss (away), middle
        ]
        let form = RecentForm.lastFiveByAbbreviation(in: season)
        #expect(letters(form["POR"]) == "WLD")
    }

    @Test func capsAtFiveMostRecent() {
        // Seven POR wins; only the last five survive.
        let season = (1...7).map { i in
            match("POR", 2, "OPP\(i)", 0, date: String(format: "2026-04-%02dT17:00Z", i))
        }
        let form = RecentForm.lastFiveByAbbreviation(in: season)
        #expect(letters(form["POR"]) == "WWWWW")
        #expect(form["POR"]?.count == 5)
    }

    @Test func ignoresUnfinishedMatches() {
        // A scheduled ("pre") and an in-progress ("in") match must not count.
        let season = [
            match("POR", 1, "KC", 0, state: "post", date: "2026-03-01T17:00Z"),
            match("POR", 0, "BAY", 0, state: "in",  date: "2026-03-08T17:00Z"),
            match("POR", 5, "SEA", 0, state: "pre", date: "2026-03-15T17:00Z"),
        ]
        let form = RecentForm.lastFiveByAbbreviation(in: season)
        #expect(letters(form["POR"]) == "W")
    }

    @Test func skipsMatchesWithMissingScores() {
        // A completed match with a nil score (abandoned/odd ESPN payload) is skipped.
        let season = [
            match("POR", nil, "KC", 1, date: "2026-03-01T17:00Z"),
            match("POR", 2, "BAY", 1, date: "2026-03-08T17:00Z"),
        ]
        let form = RecentForm.lastFiveByAbbreviation(in: season)
        #expect(letters(form["POR"]) == "W")
    }

    @Test func singleClubConvenienceMatchesMap() {
        let season = [
            match("POR", 0, "KC", 2, date: "2026-03-01T17:00Z"),
        ]
        #expect(letters(RecentForm.lastFive(forAbbreviation: "POR", in: season)) == "L")
        #expect(letters(RecentForm.lastFive(forAbbreviation: "KC", in: season)) == "W")
        #expect(RecentForm.lastFive(forAbbreviation: "NONE", in: season).isEmpty)
    }
}
