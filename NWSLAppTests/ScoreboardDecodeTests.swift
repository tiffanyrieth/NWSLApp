//
//  ScoreboardDecodeTests.swift
//  NWSLAppTests
//
//  Decode-only guard for the `Scoreboard`/`Event` helpers against a REAL captured payload
//  (NWSLAppTests/Fixtures/scoreboard.json — LOU 2-1 CHI finished 2026-08-01, ORL v LOU upcoming
//  2026-08-07). These pin the ESPN quirks the app decodes defensively: String scores, the
//  seconds-LESS kickoff date (`…T20:00Z`, no `:ss`), the LOCAL-timezone `dayKey` grouping, and the
//  `post`≠final rule. The fixture is read straight off disk via `#filePath` (no bundle wiring),
//  same as MatchSummaryTests.
//

import Foundation
import Testing
@testable import NWSLApp

struct ScoreboardDecodeTests {

    private func loadScoreboard() throws -> Scoreboard {
        let fixture = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures/scoreboard.json")
        let data = try Data(contentsOf: fixture)
        return try JSONDecoder().decode(Scoreboard.self, from: data)
    }

    private func event(_ board: Scoreboard, id: String) -> Event? {
        board.events.first { $0.id == id }
    }

    @Test func decodesBothEvents() throws {
        let board = try loadScoreboard()
        #expect(board.events.count == 2)
    }

    /// The finished match: String scores (never Int), both competitors present, and a settled result.
    @Test func finishedMatchDecodesStringScoresAndSettledResult() throws {
        let board = try loadScoreboard()
        let finished = try #require(event(board, id: "401853957"))

        // Both sides present; find LOU regardless of home/away.
        let sides = [finished.homeCompetitor, finished.awayCompetitor].compactMap { $0 }
        #expect(sides.count == 2)
        let lou = try #require(sides.first { $0.team?.abbreviation == "LOU" })
        #expect(lou.score == "2")          // String, not Int — the ESPN quirk

        #expect(finished.statusState == "post")
        #expect(finished.isFinalResult)        // post + completed → settled
        #expect(!finished.isUnfinishedPost)
    }

    /// The seconds-LESS kickoff (`2026-08-01T20:00Z`) must parse to the exact UTC instant, and `dayKey`
    /// must report the LOCAL calendar day of that instant (not the UTC day).
    @Test func parsesSecondsLessKickoffAndLocalDayKey() throws {
        let board = try loadScoreboard()
        let finished = try #require(event(board, id: "401853957"))

        var utc = Calendar(identifier: .gregorian); utc.timeZone = .gmt
        let expectedInstant = utc.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 20, minute: 0))
        let kickoff = try #require(finished.kickoff)
        #expect(kickoff == expectedInstant)

        // dayKey groups by the fan's LOCAL day — assert it equals the local Y-M-D of the same instant.
        let local = Calendar.current.dateComponents([.year, .month, .day], from: kickoff)
        let expectedDay = String(format: "%04d-%02d-%02d", local.year!, local.month!, local.day!)
        #expect(finished.dayKey == expectedDay)
    }

    /// An upcoming match is `pre`, never a settled result.
    @Test func upcomingMatchIsNotFinal() throws {
        let board = try loadScoreboard()
        let upcoming = try #require(event(board, id: "401853965"))
        #expect(upcoming.statusState == "pre")
        #expect(!upcoming.isFinalResult)
        #expect(upcoming.kickoff != nil)
    }

    /// Attendance rides the scoreboard payload (frozen-attendance regression, 2026-08-09: the
    /// `/summary` copy can sit behind a long edge-cache TTL, so match detail prefers THIS one).
    /// The finished match carries the real figure; ESPN's `0` means "unknown", which
    /// `Event.attendance` must nil out so no consumer can ever print "Attendance: 0".
    @Test func decodesAttendanceAndNilsESPNZero() throws {
        let board = try loadScoreboard()

        let finished = try #require(event(board, id: "401853957"))
        #expect(finished.competitions?.first?.attendance == 5148)
        #expect(finished.attendance == 5148)

        let upcoming = try #require(event(board, id: "401853965"))
        #expect(upcoming.competitions?.first?.attendance == 0)   // raw decode keeps ESPN's value…
        #expect(upcoming.attendance == nil)                      // …the Event helper applies zero-is-unknown
    }
}
