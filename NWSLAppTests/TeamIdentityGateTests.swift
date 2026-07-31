//
//  TeamIdentityGateTests.swift
//  NWSLAppTests
//
//  Pins the "follows one team → drop per-card team identity" rule (owner, 2026-07-31).
//
//  The rule itself is one comparison; what these tests protect is that it has ONE definition.
//  Home, the Home content list and Feed each used to spell out `count <= 1` inline — the same
//  shape that let the Bracket rank line drift across four call sites into two different
//  thresholds and two rounding rules, so the same fan saw different numbers on different screens.
//

import Testing
@testable import NWSLApp

struct TeamIdentityGateTests {

    @Test func oneTeamHidesIdentityBecauseEveryCardWouldBeTheSameClub() {
        // The stripe, badge and name all encode "which club" — worth nothing when there's only one.
        #expect(ContentCardView.hidesTeamIdentity(followedTeamCount: 1) == true)
    }

    @Test func twoOrMoreTeamsShowIdentitySoCardsAreTellableApart() {
        // The case the colour bar exists for: purple = Pride, yellow = Utah, no reading required.
        #expect(ContentCardView.hidesTeamIdentity(followedTeamCount: 2) == false)
        #expect(ContentCardView.hidesTeamIdentity(followedTeamCount: 3) == false)
        #expect(ContentCardView.hidesTeamIdentity(followedTeamCount: 16) == false)
    }

    @Test func zeroTeamsAlsoHides() {
        // No follows → nothing team-specific to distinguish. Must not crash or flip the rule.
        #expect(ContentCardView.hidesTeamIdentity(followedTeamCount: 0) == true)
    }

    @Test func theThresholdIsExactlyBetweenOneAndTwo() {
        // Guards the boundary itself: moving it silently would change every Home card's look.
        let hidden = (0...16).filter { ContentCardView.hidesTeamIdentity(followedTeamCount: $0) }
        #expect(hidden == [0, 1])
    }
}
