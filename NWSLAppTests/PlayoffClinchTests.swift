//
//  PlayoffClinchTests.swift
//  NWSLAppTests
//
//  Locks the conservative clinch/elimination math (PlayoffClinch) — the gate for the Schedule
//  tab's Playoffs chip. The tiebreaker-safety case is the critical one: a team that rivals can
//  still EQUAL on points must NOT read as clinched (strict inequality — we'd rather detect a
//  clinch late than ever claim one wrongly). Also covers the events→table computation and the
//  SeasonWindow decode against the real captured ESPN payloads.
//

import Foundation
import Testing
@testable import NWSLApp

struct PlayoffClinchTests {

    /// A 14-team league (26 games each). Helper keeps the table terse.
    private func line(_ abbr: String, _ pts: Int, _ gp: Int, _ rank: Int) -> PlayoffClinch.TeamLine {
        PlayoffClinch.TeamLine(abbreviation: abbr, points: pts, gamesPlayed: gp, rank: rank)
    }

    // MARK: Clinch

    @Test func clearlyClinchedTeamClinches() {
        // 14 teams; KC on 58 pts with rivals below 8th able to reach at most 40 → 6 uncatchable
        // needed (14−8). Bottom 6 max out below 58.
        var table = [line("KC", 58, 24, 1), line("A", 50, 24, 2), line("B", 48, 24, 3),
                     line("C", 46, 24, 4), line("D", 44, 24, 5), line("E", 42, 24, 6),
                     line("F", 40, 24, 7), line("G", 38, 24, 8)]
        table += [line("H", 30, 24, 9), line("I", 28, 24, 10), line("J", 26, 24, 11),
                  line("K", 24, 24, 12), line("L", 20, 24, 13), line("M", 10, 24, 14)]
        // Bottom six ceilings: 30+6=36 … 10+6=16 — all strictly below 58.
        #expect(PlayoffClinch.isClinched(table[0], table: table))
        #expect(PlayoffClinch.clinched(in: table).contains("KC"))
    }

    @Test func catchableOnPointsMustNotClinch() {
        // TIEBREAKER SAFETY: every rival can still reach ≥ the leader's 50 points (equal counts
        // as catchable — strict math). 45+6=51 and 44+6=50 → zero uncatchable rivals ⇒ the
        // leader must NOT read as clinched, even though it leads by 5 with 2 to play.
        var table = [line("KC", 50, 24, 1)]
        table += (2...8).map { line("T\($0)", 45, 24, $0) }    // ceiling 51 > 50 → catchable
        table += (9...14).map { line("U\($0)", 44, 24, $0) }   // ceiling 50 == 50 → catchable (strict)
        #expect(PlayoffClinch.isClinched(table[0], table: table) == false)
    }

    @Test func midSeasonNobodyClinches() {
        // 10 games in: everyone has 16 games (48 pts) of runway — no clinches possible.
        let table = (1...14).map { line("T\($0)", 30 - $0, 10, $0) }
        #expect(PlayoffClinch.clinched(in: table).isEmpty)
    }

    @Test func simulatorClinchTableHasTwoClinches() {
        // The DEBUG clinchWindow stage must actually trigger the chip's 2+ rule.
        let clinched = PlayoffClinch.clinched(in: PostseasonSimulator.clinchTable)
        #expect(clinched.contains("KC"))
        #expect(clinched.contains("WAS"))
        #expect(clinched.count >= 2)
    }

    // MARK: Elimination + status

    @Test func eliminatedAndStatusLines() {
        // 14-team, 26-game table, GP 24 → 2 games left, ceiling = pts + 6.
        let table = PostseasonSimulator.clinchTable
        // CHI (10 → ceiling 16) is below ≥8 teams' current points → eliminated.
        #expect(PlayoffClinch.status(of: "CHI", table: table) == .eliminated)
        // KC (58): 12 rivals can't reach 58 (only WAS ties) → clinched.
        #expect(PlayoffClinch.status(of: "KC", table: table) == .clinched)
        // SEA (38): the 6 teams below (NC 31 ↓, ceilings ≤ 37) can't catch it → clinched.
        #expect(PlayoffClinch.status(of: "SEA", table: table) == .clinched)
        // GFC (33, rank 8): only 4 rivals uncatchable (<6) AND not below 8 teams → in position.
        #expect(PlayoffClinch.status(of: "GFC", table: table) == .inPosition(rank: 8, gamesLeft: 2))
        // NC (31, rank 9): neither clinched nor eliminated, but below the line → out of picture.
        #expect(PlayoffClinch.status(of: "NC", table: table) == .outOfPicture)
        #expect(PlayoffClinch.status(of: "ZZZ", table: table) == nil)
    }

    // MARK: Events → table

    @Test func tableComputedFromRegularSeasonEvents() {
        // Build 3 finished games + 1 playoff game (must be excluded) + 1 future game.
        func game(_ id: String, slug: String, home: (String, Int?), away: (String, Int?), state: String) -> Event {
            Event(id: id, date: "2026-05-01T17:00Z",
                  status: EventStatus(type: StatusType(state: state)),
                  competitions: [Competition(competitors: [
                      Competitor(homeAway: "home", score: home.1.map(String.init), team: Team(abbreviation: home.0)),
                      Competitor(homeAway: "away", score: away.1.map(String.init), team: Team(abbreviation: away.0)),
                  ])],
                  season: EventSeason(year: 2026, slug: slug))
        }
        let events = [
            game("1", slug: "regular-season", home: ("A", 2), away: ("B", 0), state: "post"),   // A win
            game("2", slug: "regular-season", home: ("B", 1), away: ("C", 1), state: "post"),   // draw
            game("3", slug: "regular-season", home: ("C", 0), away: ("A", 3), state: "post"),   // A win
            game("4", slug: "playoffs---quarterfinals", home: ("A", 9), away: ("B", 0), state: "post"), // excluded
            game("5", slug: "regular-season", home: ("A", nil), away: ("C", nil), state: "pre"), // future
        ]
        let table = PlayoffClinch.table(fromRegularSeason: events)
        #expect(table.count == 3)
        let a = table.first { $0.abbreviation == "A" }
        #expect(a?.points == 6)          // two wins — the playoff rout must NOT count
        #expect(a?.gamesPlayed == 2)
        #expect(a?.rank == 1)
        let b = table.first { $0.abbreviation == "B" }
        #expect(b?.points == 1)
        // C (draw, GD −3) vs B (draw, GD −3, fewer GF)… rank order is deterministic.
        #expect(table.map(\.abbreviation).first == "A")
    }

    // MARK: SeasonWindow decode (real captured payloads)

    private func fixtureURL(_ name: String) -> URL {
        URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/\(name)")
    }

    @Test func decodesSeasonTypeListAndDetail() throws {
        let listData = try Data(contentsOf: fixtureURL("season-types-2026.json"))
        let list = try JSONDecoder().decode(SeasonTypeList.self, from: listData)
        #expect((list.items ?? []).count == 4)
        #expect(list.items?.first?.ref?.contains("/types/1") == true)

        let detailData = try Data(contentsOf: fixtureURL("season-type-detail-2026.json"))
        let window = try JSONDecoder().decode(SeasonWindow.self, from: detailData)
        #expect(window.slug == "playoffs---quarterfinals")
        #expect(window.isPlayoff)
        #expect(window.round == .quarterfinal)
        #expect(window.start != nil)
        #expect(window.end != nil)
    }
}
