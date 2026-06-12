//
//  PlayerSpotlightTests.swift
//  NWSLAppTests
//
//  Decode test for the live Player Spotlight (B2): the app↔proxy contract. Decodes
//  a real captured `/spotlight` response (NWSLAppTests/Fixtures/spotlight.json —
//  WAS + KC) into `[PlayerSpotlight]` and guards the live-backend fields
//  (espnAthleteId, seasonStatLine) plus the `statStrip` preference logic that
//  routes the card/detail strip to real stats when present, else the seed's
//  `demoSeasonStats`.
//
//  The fixture is read straight off disk via #filePath (like AthleteStatisticsTests),
//  so it needs no test-bundle resource membership.
//

import Foundation
import Testing
@testable import NWSLApp

struct PlayerSpotlightTests {

    private func loadSpotlights() throws -> [PlayerSpotlight] {
        let fixture = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures/spotlight.json")
        let data = try Data(contentsOf: fixture)
        return try JSONDecoder().decode([PlayerSpotlight].self, from: data)
    }

    @Test func decodesLiveSpotlightContract() throws {
        let spotlights = try loadSpotlights()
        #expect(spotlights.count == 2)

        let kc = try #require(spotlights.first { $0.teamAbbreviation == "KC" })
        #expect(kc.playerName == "Croix Bethune")
        #expect(kc.jerseyNumber == 8)
        // The live-backend fields the seed never carried.
        #expect(kc.espnAthleteId == "296207")
        #expect(kc.seasonStatLine == .init(goals: 2, assists: 3, apps: 12))
        // The Haiku "why watch" blurb lands in bioBlurb (required, never empty).
        #expect(!kc.bioBlurb.isEmpty)
        // Live cards carry no curated highlights/facts and no video (v1).
        #expect(kc.careerHighlights.isEmpty)
        #expect(kc.funFacts.isEmpty)
        #expect(kc.videoURL == nil)
    }

    @Test func statStripPrefersRealBackendStats() throws {
        let kc = try #require(loadSpotlights().first { $0.teamAbbreviation == "KC" })
        // With a real seasonStatLine, the strip shows it (NOT the jersey-derived demo).
        #expect(kc.statStrip.goals == 2)
        #expect(kc.statStrip.assists == 3)
        #expect(kc.statStrip.apps == 12)
    }

    @Test func statStripFallsBackToDemoWhenNoBackendStats() {
        // A seed-style spotlight (no seasonStatLine) falls back to demoSeasonStats —
        // the offline-first fallback path renders unchanged.
        let seed = PlayerSpotlight(
            id: "seed-1",
            teamAbbreviation: "WAS",
            playerName: "Demo Player",
            jerseyNumber: 10,
            position: "Forward",
            bioBlurb: "A seed spotlight.",
            videoURL: nil,
            youTubeVideoID: nil,
            videoTitle: nil,
            videoSource: nil,
            nationality: nil,
            age: nil,
            careerHighlights: [],
            funFacts: [],
            seasonForm: nil
        )
        #expect(seed.seasonStatLine == nil)
        let demo = seed.demoSeasonStats
        #expect(seed.statStrip.goals == demo.goals)
        #expect(seed.statStrip.assists == demo.assists)
        #expect(seed.statStrip.apps == demo.apps)
    }
}
