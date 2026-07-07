//
//  PlayoffDerivationTests.swift
//  NWSLAppTests
//
//  Locks the playoff-bracket derivation against the REAL 2025 NWSL postseason (captured
//  fixtures: Fixtures/playoffs-2025-scoreboard.json + standings-2025.json). Covers the
//  seed-tree math, round grouping, seeding, the "Win →" projection, the multi-team
//  storyline, the eliminated-team path, and the format tripwire. Read straight off disk via
//  #filePath (like MatchWeatherTests) — no bundle membership needed.
//

import Foundation
import Testing
@testable import NWSLApp

struct PlayoffDerivationTests {

    // MARK: Fixture loading

    private func fixtureURL(_ name: String) -> URL {
        URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/\(name)")
    }
    private func events2025() throws -> [Event] {
        let data = try Data(contentsOf: fixtureURL("playoffs-2025-scoreboard.json"))
        return try JSONDecoder().decode(Scoreboard.self, from: data).events
    }
    private func seeds2025() throws -> [String: Int] {
        let data = try Data(contentsOf: fixtureURL("standings-2025.json"))
        let rows = try JSONDecoder().decode(StandingsResponse.self, from: data).rows
        return Dictionary(rows.map { ($0.club.abbreviation, $0.rank) }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: EventSeason decode

    @Test func decodesSeasonSlug() throws {
        let events = try events2025()
        let playoffs = events.filter { $0.isPlayoffEvent }
        #expect(playoffs.count == 7)   // 4 QF + 2 SF + 1 Championship
        #expect(events.contains { $0.seasonSlug == "playoffs---quarterfinals" })
        #expect(events.contains { $0.seasonSlug == "playoffs---championship" })
        #expect(events.contains { $0.isRegularSeasonEvent })
    }

    // MARK: Seed tree

    @Test func seedTreeIsStandardBracket() {
        let t = SeedTree(teamCount: 8)
        #expect(t.roundCount == 3)
        #expect(t.matchupsPerRound == [4, 2, 1])
        #expect(t.firstRoundSeeds.map { [$0.0, $0.1] } == [[1, 8], [4, 5], [2, 7], [3, 6]])
        #expect(t.feeders[1].map { [$0.0, $0.1] } == [[0, 1], [2, 3]])
        #expect(t.feeders[2].map { [$0.0, $0.1] } == [[0, 1]])
    }

    @Test func seedTreeSnapsToPowerOfTwo() {
        #expect(SeedTree(teamCount: 8).teamCount == 8)
        #expect(SeedTree(teamCount: 6).teamCount == 8)   // defensive snap
        #expect(SeedTree(teamCount: 4).roundCount == 2)
    }

    // MARK: Full 2025 bracket

    @Test func derivesFullBracketWithGothamChampion() throws {
        let b = PlayoffBracket.derive(from: try events2025(), seeds: try seeds2025())
        #expect(b.rounds.count == 3)
        #expect(b.matchups(in: .quarterfinal).count == 4)
        #expect(b.matchups(in: .semifinal).count == 2)
        #expect(b.matchups(in: .championship).count == 1)
        #expect(b.formatConsistent)
        #expect(b.tripwireReason == nil)
        #expect(b.championship?.winnerAbbreviation == "GFC")
    }

    @Test func quarterfinalPairingsMatchSeeds() throws {
        let b = PlayoffBracket.derive(from: try events2025(), seeds: try seeds2025())
        // Every QF is a higher-vs-lower seed pair from the standard bracket.
        let pairs = b.matchups(in: .quarterfinal).map { Set([$0.home.seed, $0.away.seed]) }
        #expect(pairs.contains(Set([1, 8])))
        #expect(pairs.contains(Set([4, 5])))
        #expect(pairs.contains(Set([2, 7])))
        #expect(pairs.contains(Set([3, 6])))
        // Higher seed hosts.
        for m in b.matchups(in: .quarterfinal) {
            #expect((m.home.seed ?? 99) < (m.away.seed ?? 99))
        }
    }

    @Test func onlyTopEightAreInBracket() throws {
        let b = PlayoffBracket.derive(from: try events2025(), seeds: try seeds2025())
        #expect(b.seeds["KC"] == 1)
        #expect(b.seeds["GFC"] == 8)
        #expect(b.seeds["NC"] == nil)   // #9 — missed the playoffs, not in the bracket
        #expect(b.isAlive("NC") == false)
    }

    // MARK: Win → projection (mid-tournament: some QFs decided, WAS's not — the real state
    // the projection is FOR. Driven off the real-data simulator's midRun snapshot).

    @Test func projectsSemifinalOpponentBeforePublished() {
        let (events, seeds, now) = PostseasonSimulator.snapshot(.midRun)
        let b = PlayoffBracket.derive(from: events, seeds: seeds, now: now)
        #expect(b.formatConsistent)                        // partial data must NOT trip the wire
        #expect(b.matchups(in: .semifinal).count == 2)     // SF projected
        // WAS's QF is LIVE (not decided) → frontier QF; POR won the 3v6 that feeds WAS's SF slot.
        let wasStep = b.path(forAbbreviation: "WAS")?.first
        #expect(wasStep?.round == .quarterfinal)
        #expect(wasStep?.winContext == "face POR in the Semifinal")
    }

    @Test func semifinalSlotsCarryKnownQualifiers() {
        let (events, seeds, now) = PostseasonSimulator.snapshot(.midRun)
        let b = PlayoffBracket.derive(from: events, seeds: seeds, now: now)
        // ORL (won 4v5) and POR (won 3v6) advanced → each placed in an SF slot opposite a TBD.
        let sfTeams = b.matchups(in: .semifinal).flatMap { [$0.home.abbreviation, $0.away.abbreviation] }
        #expect(sfTeams.contains("ORL"))
        #expect(sfTeams.contains("POR"))
        #expect(sfTeams.contains(nil))   // KC/GFC & WAS/LOU winners still TBD
    }

    // MARK: Multi-team storyline

    @Test func storylineWhenTwoTeamsCouldMeet() {
        // qfUpcoming = every QF still to play → all 8 alive.
        let (events, seeds, now) = PostseasonSimulator.snapshot(.qfUpcoming)
        let b = PlayoffBracket.derive(from: events, seeds: seeds, now: now)
        // GFC (1v8, top half) and WAS (2v7, bottom half) → could only meet in the Final.
        let s = b.storyline(between: "GFC", and: "WAS")
        #expect(s?.round == .championship)
        #expect(s?.text.contains("GFC") == true)
        // WAS and LOU are in the SAME quarterfinal → they can't both win → no storyline.
        #expect(b.storyline(between: "WAS", and: "LOU") == nil)
    }

    // MARK: Eliminated team

    @Test func eliminatedTeamPathStopsAtExit() throws {
        let b = PlayoffBracket.derive(from: try events2025(), seeds: try seeds2025())
        // SEA lost in the QF → path is exactly one step (its QF), no phantom SF/Final.
        #expect(b.eliminationRound("SEA") == .quarterfinal)
        let path = b.path(forAbbreviation: "SEA")
        #expect(path?.count == 1)
        #expect(path?.first?.round == .quarterfinal)
        #expect(path?.first?.winContext == nil)   // no "Win →" once eliminated
        // WAS reached the final and lost it.
        #expect(b.eliminationRound("WAS") == .championship)
        #expect(b.isAlive("GFC"))
    }

    // MARK: Format tripwire

    @Test func tripwireFiresOnUnknownRoundSlug() throws {
        // A future ESPN round we don't recognize (a real format change) → degrade + alert.
        var events = try events2025()
        events.append(Event(
            id: "fake", date: "2025-11-05T22:00Z",
            status: EventStatus(type: StatusType(state: "pre")),
            competitions: [Competition(competitors: [
                Competitor(homeAway: "home", team: Team(abbreviation: "NC")),
                Competitor(homeAway: "away", team: Team(abbreviation: "HOU")),
            ])],
            season: EventSeason(year: 2025, slug: "playoffs---wildcard-round")
        ))
        let b = PlayoffBracket.derive(from: events, seeds: try seeds2025())
        #expect(b.formatConsistent == false)
        #expect(b.tripwireReason != nil)
    }

    @Test func cleanBracketDoesNotTrip() throws {
        // Sanity: the real, complete bracket must never trip the wire.
        let b = PlayoffBracket.derive(from: try events2025(), seeds: try seeds2025())
        #expect(b.formatConsistent)
    }
}
