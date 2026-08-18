//
//  ScheduleFilterTests.swift
//  NWSLAppTests
//
//  The Schedule chip filter (`ScheduleViewModel.matches(for:in:followedAbbreviations:)`),
//  tested through the extracted pure static — no live store needed. Locks the 2026-08-18
//  rule: the "All" overview weaves in EVERY NWSL-club CONCACAF match (regardless of follow)
//  plus your followed national teams, while "My teams" narrows clubs to your follows and
//  "Playoffs" stays NWSL-only. CONCACAF is core content now (the opt-in toggle was retired).
//

import Foundation
import Testing
@testable import NWSLApp

struct ScheduleFilterTests {

    private func event(home: String, away: String) -> Event {
        Event(id: UUID().uuidString,
              competitions: [Competition(competitors: [
                  Competitor(homeAway: "home", team: Team(id: home, abbreviation: home)),
                  Competitor(homeAway: "away", team: Team(id: away, abbreviation: away)),
              ])])
    }

    private func match(_ competition: CompetitionType, home: String, away: String) -> ScheduledMatch {
        ScheduledMatch(event: event(home: home, away: away), competition: competition)
    }

    // A followed club (POR), a NON-followed NWSL club (BAY) in CONCACAF, a followed
    // national team (ZAM), and a plain league match.
    private var sample: [ScheduledMatch] {
        [
            match(.nwsl, home: "POR", away: "WAS"),                     // league
            match(.challengeCup, home: "POR", away: "KC"),             // NWSL cup
            match(.concacafChampionsCup, home: "POR", away: "TIG"),    // followed club in CONCACAF
            match(.concacafChampionsCup, home: "BAY", away: "AME"),    // NON-followed club in CONCACAF
            match(.international("WAFCON"), home: "ZAM", away: "EGY"),  // followed national team
        ]
    }

    private let followed: Set<String> = ["POR"]   // only Portland followed

    @Test func allOverviewIncludesEveryNWSLClubConcacafAndFollowedNTs() {
        let result = ScheduleViewModel.matches(for: .nwsl, in: sample, followedAbbreviations: followed)
        // The overview is the whole curated set — including BAY's CONCACAF match (a
        // non-followed club) and the followed national-team match.
        #expect(result.count == sample.count)
        #expect(result.contains { $0.competition == .concacafChampionsCup
            && $0.event.homeCompetitor?.team?.abbreviation == "BAY" })
        #expect(result.contains { if case .international = $0.competition { return true }; return false })
    }

    @Test func myTeamsNarrowsClubsButKeepsFollowedNTs() {
        let result = ScheduleViewModel.matches(for: .myTeams, in: sample, followedAbbreviations: followed)
        // POR's league + cup + CONCACAF matches, plus the followed NT — but NOT BAY's
        // CONCACAF match (BAY isn't followed).
        #expect(result.count == 4)
        #expect(!result.contains { $0.event.homeCompetitor?.team?.abbreviation == "BAY" })
        #expect(result.contains { if case .international = $0.competition { return true }; return false })
    }

    @Test func playoffsStaysNWSLOnly() {
        let result = ScheduleViewModel.matches(for: .playoffs, in: sample, followedAbbreviations: followed)
        // Only NWSL-schedule competitions (league + Challenge Cup); no CONCACAF, no NT.
        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.competition.inNWSLScheduleView })
    }
}
