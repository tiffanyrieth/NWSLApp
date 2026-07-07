//
//  PlayoffOverrideTests.swift
//  NWSLAppTests
//
//  Exercises the operator override escape hatch (PlayoffOverride) end-to-end through the pure
//  derivation, so the path that only runs when ESPN breaks is actually verified — not untested
//  scaffolding. Uses the real-data postseason simulator's midRun snapshot as the base state.
//

import Foundation
import Testing
@testable import NWSLApp

struct PlayoffOverrideTests {

    private func midRun() -> (events: [Event], seeds: [String: Int], now: Date) {
        PostseasonSimulator.snapshot(.midRun)
    }

    // MARK: Decode (what the proxy serves)

    @Test func decodesOverrideEnvelope() throws {
        let jsonString = """
        {"version":1,"season":2026,"override":{
          "note":"ESPN dropped the SF winner",
          "hideBracket":false,
          "teamCount":8,
          "seeds":{"WAS":1},
          "matchups":[{"round":"playoffs---semifinals","home":"WAS","away":"POR",
            "homeScore":2,"awayScore":0,"winner":"WAS","state":"post",
            "kickoff":"2026-11-15T17:00Z","broadcast":"CBS","venue":"Audi Field"}]
        }}
        """
        let env = try JSONDecoder().decode(PlayoffOverrideEnvelope.self, from: Data(jsonString.utf8))
        let o = try #require(env.override)
        #expect(o.teamCount == 8)
        #expect(o.seeds?["WAS"] == 1)
        #expect(o.matchups?.first?.winner == "WAS")
        #expect(o.matchups?.first?.venue == "Audi Field")
        #expect(o.isEmpty == false)
    }

    @Test func nullOverrideDecodesToNil() throws {
        let env = try JSONDecoder().decode(PlayoffOverrideEnvelope.self,
                                           from: Data(#"{"version":1,"season":2026,"override":null}"#.utf8))
        #expect(env.override == nil)
    }

    // MARK: Correcting a game propagates to later rounds

    @Test func patchInjectsResultAndPropagates() {
        let (events, seeds, now) = midRun()
        // ESPN hasn't published KC/GFC yet (it's upcoming) — operator injects the real result: GFC won.
        let override = PlayoffOverride(
            note: nil, hideBracket: nil, teamCount: nil, seeds: nil,
            matchups: [MatchupPatch(round: "playoffs---quarterfinals", home: "KC", away: "GFC",
                                    homeScore: 1, awayScore: 2, winner: "GFC", state: "post",
                                    kickoff: nil, broadcast: nil, venue: nil)])
        let c = override.corrected(events: events, seeds: seeds)
        let b = PlayoffBracket.derive(from: c.events, seeds: c.seeds, now: now)
        // GFC now advances to the semifinal; KC is eliminated.
        let sfTeams = b.matchups(in: .semifinal).flatMap { [$0.home.abbreviation, $0.away.abbreviation] }
        #expect(sfTeams.contains("GFC"))
        #expect(b.isAlive("KC") == false)
        #expect(b.isAlive("GFC"))
    }

    @Test func correctsAWrongWinner() {
        let (events, seeds, now) = midRun()
        // Suppose ESPN mis-reported ORL/SEA (it really was ORL 2-0). Operator flips it to SEA.
        let override = PlayoffOverride(
            note: nil, hideBracket: nil, teamCount: nil, seeds: nil,
            matchups: [MatchupPatch(round: "playoffs---quarterfinals", home: "ORL", away: "SEA",
                                    homeScore: 0, awayScore: 1, winner: "SEA", state: "post",
                                    kickoff: nil, broadcast: nil, venue: nil)])
        let c = override.corrected(events: events, seeds: seeds)
        let b = PlayoffBracket.derive(from: c.events, seeds: c.seeds, now: now)
        let sfTeams = b.matchups(in: .semifinal).flatMap { [$0.home.abbreviation, $0.away.abbreviation] }
        #expect(sfTeams.contains("SEA"))
        #expect(b.isAlive("ORL") == false)
    }

    // MARK: Seed + teamCount overrides

    @Test func seedOverrideMerges() {
        let (_, seeds, _) = midRun()
        let override = PlayoffOverride(note: nil, hideBracket: nil, teamCount: nil,
                                       seeds: ["ZZZ": 3], matchups: nil)
        let c = override.corrected(events: [], seeds: seeds)
        #expect(c.seeds["ZZZ"] == 3)          // added
        #expect(c.seeds["KC"] == seeds["KC"]) // untouched
    }

    @Test func forcedTeamCountWinsOverDataDerivation() {
        let (events, _, now) = midRun()
        // Only two QFs published → naive derivation would infer a 4-team bracket…
        let partial = events.filter { ($0.homeCompetitor?.team?.abbreviation).map { ["ORL", "POR"].contains($0) } ?? false }
        let seeds = PostseasonSimulator.seeds2025
        #expect(PlayoffBracket.derive(from: partial, seeds: seeds, now: now).teamCount == 4)
        // …the operator override pins the true size.
        #expect(PlayoffBracket.derive(from: partial, seeds: seeds, now: now, forcedTeamCount: 8).teamCount == 8)
    }
}
