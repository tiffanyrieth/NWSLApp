//
//  MatchSummaryTests.swift
//  NWSLAppTests
//
//  Decode-only test for MatchSummary against a real captured ESPN `/summary`
//  response (NWSLAppTests/Fixtures/summary.json — WAS 1-1 POR, 2026-03-14).
//  Guards the defensive decoder + helper accessors against ESPN's real shape
//  and its type quirks (String jersey/formationPlace, nullable stat values).
//
//  The fixture is read straight off disk via #filePath (the path of this source
//  file), so it needs no test-bundle resource membership.
//

import Foundation
import Testing
@testable import NWSLApp

struct MatchSummaryTests {

    /// Loads + decodes the captured summary fixture once per test.
    private func loadSummary() throws -> MatchSummary {
        let fixture = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures/summary.json")
        let data = try Data(contentsOf: fixture)
        return try JSONDecoder().decode(MatchSummary.self, from: data)
    }

    @Test func decodesRostersAndFormation() throws {
        let summary = try loadSummary()

        // Two rosters, split cleanly by homeAway with a parsed formation string.
        #expect(summary.rosters?.count == 2)
        let home = try #require(summary.homeRoster)
        let away = try #require(summary.awayRoster)
        #expect(home.formation == "4-2-3-1")
        #expect(away.formation != nil)
    }

    @Test func startersAreElevenInFormationOrder() throws {
        let summary = try loadSummary()
        let home = try #require(summary.homeRoster)

        // Exactly 11 starters, and they sort by formationPlace (1 = GK first).
        #expect(home.starters.count == 11)
        let places = home.starters.compactMap { $0.formationPlaceValue }
        #expect(places.first == 1)
        #expect(places == places.sorted())

        // The String → Int parse worked, and jersey/position live on the player.
        let gk = try #require(home.starters.first)
        #expect(gk.position?.abbreviation == "G")
        #expect(gk.jersey != nil)
        #expect(gk.athlete?.id != nil)
    }

    @Test func boxscoreStatsLookUpByName() throws {
        let summary = try loadSummary()
        let homeBox = try #require(summary.homeBoxscore)

        // displayValue is always present; the lookup-by-name helper resolves it.
        let possession = try #require(homeBox.stat("possessionPct"))
        #expect(possession.displayValue == "61")
        #expect(homeBox.stat("totalShots")?.displayValue == "12")
        // Unknown key returns nil rather than crashing.
        #expect(homeBox.stat("notAStat") == nil)
    }

    @Test func keyEventsExposeGoals() throws {
        let summary = try loadSummary()

        // The timeline keeps participant/scoring events and drops neutral markers.
        let timeline = summary.timelineEvents
        #expect(!timeline.isEmpty)

        let goal = try #require(summary.keyEvents?.first { $0.type?.type == "goal" })
        #expect(goal.clock?.displayValue?.isEmpty == false)   // e.g. "52'"
        #expect(goal.participants?.first?.athlete?.displayName != nil)
    }

    @Test func gameInfoDecodes() throws {
        let summary = try loadSummary()
        #expect(summary.gameInfo?.venue?.fullName == "Audi Field")
        #expect(summary.gameInfo?.attendance == 19215)
    }

    // MARK: - SubStatus shape tolerance (regression: the "Couldn't read the match
    // details" bug). ESPN's LIVE feed sends subbedIn/subbedOut as `{"didSub": Bool}`
    // OBJECTS, while other snapshots send a bare Bool. Before SubStatus, the object
    // shape threw a DecodingError that failed the ENTIRE MatchSummary — hiding a live
    // match's full lineups. These prove the whole summary still decodes for every shape.

    /// Decode a one-player MatchSummary with the given raw JSON for the sub fields.
    private func decodePlayer(subbedIn: String, subbedOut: String) throws -> MatchPlayer {
        let json = """
        { "rosters": [ { "homeAway": "home", "roster": [
            { "athlete": { "id": "1", "displayName": "Test Player" },
              "jersey": "9", "starter": true, "formationPlace": "11",
              "subbedIn": \(subbedIn), "subbedOut": \(subbedOut) }
        ] } ] }
        """
        let summary = try JSONDecoder().decode(MatchSummary.self, from: Data(json.utf8))
        return try #require(summary.homeRoster?.roster?.first)
    }

    @Test func decodesSubStatusObjectShape() throws {
        // The LIVE shape: {"didSub": …} — must decode, not throw and kill the summary.
        let player = try decodePlayer(subbedIn: #"{"didSub": true}"#, subbedOut: #"{"didSub": false}"#)
        #expect(player.didSubIn == true)
        #expect(player.didSubOut == false)
    }

    @Test func decodesSubStatusBoolAndUnknownShapes() throws {
        // Legacy bare-Bool shape still works (backward compatible)…
        let boolPlayer = try decodePlayer(subbedIn: "true", subbedOut: "false")
        #expect(boolPlayer.didSubIn == true)
        #expect(boolPlayer.didSubOut == false)

        // …and an unexpected/absent shape degrades to `false`, never failing the decode.
        let oddPlayer = try decodePlayer(subbedIn: #"{"other": 1}"#, subbedOut: "null")
        #expect(oddPlayer.didSubIn == false)
        #expect(oddPlayer.didSubOut == false)
    }

    // MARK: - asAthlete bridge (pitch tap → PlayerDetailView). A lineup player carries
    // only id/name/jersey/position; asAthlete maps that to the roster Athlete the player
    // screen expects, and stays nil when ESPN gave no id (dot stays non-tappable).

    @Test func asAthleteBridgesPitchPlayerToRosterAthlete() throws {
        let summary = try loadSummary()
        let gk = try #require(summary.homeRoster?.starters.first)   // formationPlace 1 = GK

        let athlete = try #require(gk.asAthlete)                    // has an id → bridges
        #expect(athlete.id == gk.athlete?.id)
        #expect(athlete.jersey == gk.jersey)                       // jersey carried across
        #expect(athlete.positionAbbreviation == "G")               // position preserved…
        #expect(athlete.isGoalkeeper)                              // …→ GK stat set on detail
        #expect(athlete.name.isEmpty == false)
    }

    @Test func asAthleteIsNilWithoutAnAthleteID() throws {
        // ESPN sometimes omits the athlete node; the dot must stay non-tappable, not crash.
        let json = #"{ "rosters": [ { "homeAway": "home", "roster": [ { "jersey": "9", "starter": true } ] } ] }"#
        let summary = try JSONDecoder().decode(MatchSummary.self, from: Data(json.utf8))
        let player = try #require(summary.homeRoster?.roster?.first)
        #expect(player.asAthlete == nil)
    }

    // MARK: - Full play-by-play (commentary merged with keyEvents)
    //
    // The Play-by-Play tab merges the rich keyEvents rows (goal/card/sub, enriched with a
    // scorer + running scoreline) with the commentary-only types (shots/fouls/corners/…),
    // newest-first. Commentary's OWN goal/kickoff slugs must be dropped (no dupe of the goal,
    // no neutral markers). Team is mapped to home/away by DISPLAY NAME (commentary has no id).

    @Test func playByPlayMergesCommentaryAndKeyEventsNewestFirst() throws {
        let json = """
        {
          "keyEvents": [
            { "id": "g1", "scoringPlay": true,
              "type": { "text": "Goal", "type": "penalty---scored" },
              "clock": { "value": 3305, "displayValue": "56'" },
              "team": { "id": "H", "displayName": "Home FC" },
              "participants": [ { "athlete": { "displayName": "A. Scorer" } } ] }
          ],
          "commentary": [
            { "sequence": 1, "time": { "value": 0, "displayValue": "" }, "text": "First Half begins.",
              "play": { "type": { "text": "Kickoff", "type": "kickoff" }, "clock": { "value": 0, "displayValue": "" } } },
            { "sequence": 40, "time": { "value": 2000, "displayValue": "33'" }, "text": "Foul by an away player.",
              "play": { "type": { "text": "Foul", "type": "foul" }, "clock": { "value": 2000, "displayValue": "33'" },
                        "team": { "displayName": "Away FC" } } },
            { "sequence": 66, "time": { "value": 3300, "displayValue": "55'" }, "text": "Attempt saved.",
              "play": { "type": { "text": "Shot On Target", "type": "shot-on-target" }, "clock": { "value": 3300, "displayValue": "55'" },
                        "team": { "displayName": "Home FC" } } },
            { "sequence": 67, "time": { "value": 3305, "displayValue": "56'" }, "text": "Goal!",
              "play": { "type": { "text": "Penalty - Scored", "type": "penalty---scored" }, "clock": { "value": 3305, "displayValue": "56'" },
                        "team": { "displayName": "Home FC" } } }
          ]
        }
        """
        let summary = try JSONDecoder().decode(MatchSummary.self, from: Data(json.utf8))
        #expect(summary.commentary?.count == 4)   // all four decoded

        let items = summary.playByPlay(homeID: "H", homeDisplayName: "Home FC")
        // 3 rows: keyEvents goal + commentary shot + foul. The commentary GOAL (dupe of the
        // keyEvents row) and KICKOFF (neutral) are dropped.
        #expect(items.count == 3)
        #expect(items.map(\.kind) == [.goal, .shotOnTarget, .foul])   // newest-first by clock

        let goal = items[0]
        #expect(goal.score == "1\u{2013}0")          // running scoreline attached
        #expect(goal.primary == "A. Scorer")         // enriched scorer from keyEvents
        #expect(goal.isHome)

        #expect(items[1].primary == "Shot on target")
        #expect(items[1].isHome)                     // "Home FC" → home
        #expect(items[2].kind == .foul)
        #expect(items[2].isHome == false)            // "Away FC" → away
    }
}
