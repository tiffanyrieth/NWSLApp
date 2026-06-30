//
//  CompetitionTypeTests.swift
//  NWSLAppTests
//
//  Pins the two-concern split on CompetitionType: `isNWSL` gates the LEAGUE TABLE
//  (standings / club records / styling) while `inNWSLScheduleView` gates the Schedule
//  "NWSL" chip. The Challenge Cup is the case that distinguishes them — an NWSL
//  competition that belongs in the schedule view but stays out of the league table.
//

import Testing
@testable import NWSLApp

struct CompetitionTypeTests {
    @Test func regularSeasonCountsEverywhere() {
        #expect(CompetitionType.nwsl.isNWSL)
        #expect(CompetitionType.nwsl.inNWSLScheduleView)
    }

    @Test func challengeCupShowsInScheduleButNotStandings() {
        // The split's whole point: in the NWSL schedule chip, out of the league table.
        #expect(CompetitionType.challengeCup.isNWSL == false)
        #expect(CompetitionType.challengeCup.inNWSLScheduleView)
    }

    @Test func championsCupIsNeither() {
        #expect(CompetitionType.concacafChampionsCup.isNWSL == false)
        #expect(CompetitionType.concacafChampionsCup.inNWSLScheduleView == false)
    }

    @Test func nationalTeamIsNeither() {
        let intl = CompetitionType.international("SheBelieves Cup")
        #expect(intl.isNWSL == false)
        #expect(intl.inNWSLScheduleView == false)
    }
}
