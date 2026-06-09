//
//  MatchPreviewTests.swift
//  NWSLAppTests
//
//  Unit test for MatchDetailViewModel.buildPreview — the future-match preview
//  derives each team's season form (record, goals, points, last-5) from the
//  shared scoreboard season. Drives it with a small synthetic season decoded
//  through the real Scoreboard decoder, then checks the W/D/L + averaging math.
//

import Foundation
import Testing
@testable import NWSLApp

struct MatchPreviewTests {

    /// One event row: home/away abbreviations, optional scores, and state.
    private func eventJSON(id: String, date: String, home: String, away: String,
                           homeScore: String?, awayScore: String?, state: String) -> String {
        func competitor(_ abbr: String, _ side: String, _ score: String?) -> String {
            let scoreField = score.map { "\"score\": \"\($0)\"," } ?? ""
            return """
            { "homeAway": "\(side)", \(scoreField) "team": { "abbreviation": "\(abbr)" } }
            """
        }
        return """
        {
          "id": "\(id)", "date": "\(date)",
          "status": { "type": { "state": "\(state)" } },
          "competitions": [ { "competitors": [
            \(competitor(home, "home", homeScore)),
            \(competitor(away, "away", awayScore))
          ] } ]
        }
        """
    }

    private func decodeSeason(_ events: [String]) throws -> [Event] {
        let json = "{ \"events\": [ \(events.joined(separator: ",")) ] }"
        return try JSONDecoder().decode(Scoreboard.self, from: Data(json.utf8)).events
    }

    @Test func buildsFormFromCompletedGames() throws {
        // AAA: W (2-0), D (1-1), L (0-3) → played 3, GF 3, GA 4, pts 4, form W D L.
        let season = try decodeSeason([
            eventJSON(id: "100", date: "2026-04-01T00:00Z", home: "AAA", away: "BBB",
                      homeScore: nil, awayScore: nil, state: "pre"),               // the target match
            eventJSON(id: "1", date: "2026-03-01T00:00Z", home: "AAA", away: "CCC",
                      homeScore: "2", awayScore: "0", state: "post"),              // W
            eventJSON(id: "2", date: "2026-03-08T00:00Z", home: "DDD", away: "AAA",
                      homeScore: "1", awayScore: "1", state: "post"),              // D (away)
            eventJSON(id: "3", date: "2026-03-15T00:00Z", home: "AAA", away: "EEE",
                      homeScore: "0", awayScore: "3", state: "post"),              // L
            eventJSON(id: "4", date: "2026-09-01T00:00Z", home: "AAA", away: "FFF",
                      homeScore: nil, awayScore: nil, state: "pre"),               // future — excluded
        ])
        let target = try #require(season.first { $0.id == "100" })
        let vm = MatchDetailViewModel(event: target)

        let preview = vm.buildPreview(season: season)
        let home = preview.home   // AAA

        #expect(home.played == 3)
        #expect(home.goalsFor == 3)
        #expect(home.goalsAgainst == 4)
        #expect(home.points == 4)                      // 3 + 1 + 0
        #expect(home.recent == [.win, .draw, .loss])   // chronological
        #expect(abs(home.goalsPerMatch - 1.0) < 0.001)
        #expect(abs(home.pointsPerGame - (4.0 / 3.0)) < 0.001)
    }

    @Test func emptyWhenNoCompletedGames() throws {
        let season = try decodeSeason([
            eventJSON(id: "100", date: "2026-04-01T00:00Z", home: "AAA", away: "BBB",
                      homeScore: nil, awayScore: nil, state: "pre"),
        ])
        let target = try #require(season.first)
        let preview = MatchDetailViewModel(event: target).buildPreview(season: season)

        #expect(preview.home.played == 0)
        #expect(preview.away.played == 0)
        #expect(!preview.hasData)
    }
}
