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

/// The season-stats header names its competition on purpose.
///
/// Every stat number in the app is an ESPN Core-API line scoped to `leagues/usa.nwsl`, so it is
/// always an NWSL record — including on a player opened from a NATIONAL-TEAM match. Barbra Banda's
/// page reached from Zambia vs Egypt shows her Orlando Pride season; unlabelled ("SEASON 2026") a
/// fan can reasonably read those goals as her Zambia record. The app tracks no international stats
/// at all, so the header has to say which competition it means.
struct SeasonStatsLabelTests {

    @Test func labelNamesTheCompetition() {
        #expect(AppConfig.seasonStatsLabel(year: 2026) == "NWSL SEASON 2026")
    }

    @Test func labelIsNotBareSeasonYear() {
        // The exact ambiguity this exists to remove.
        #expect(AppConfig.seasonStatsLabel(year: 2026) != "SEASON 2026")
    }

    @Test func labelDefaultsToTheCurrentSeason() {
        #expect(AppConfig.seasonStatsLabel() == "NWSL SEASON \(AppConfig.currentSeasonYear)")
    }
}

/// The national-team browse path (2026-07-31). The pure seam worth pinning is the label↔slug
/// pair: Match Detail carries only `.international(label)`, and the tapped-player enrichment
/// needs the SLUG back — a label that silently falls out of sync with `NationalTeamFeed.all`
/// would quietly kill bio + tournament stats for that competition.
struct NationalTeamFeedTests {

    @Test func everyFeedLabelRoundTripsToItsSlug() {
        for feed in NationalTeamFeed.all {
            #expect(NationalTeamFeed.slug(forLabel: feed.label) == feed.slug)
        }
    }

    @Test func unknownLabelResolvesToNilNotAGuess() {
        #expect(NationalTeamFeed.slug(forLabel: "NWSL Regular Season") == nil)
        #expect(NationalTeamFeed.slug(forLabel: "") == nil)
    }

    @Test func friendliesLeadTheFeedOrder() {
        // nationalTeamSquad tries feeds in .all order and takes the FIRST non-empty squad.
        // Friendlies first is a deliberate choice: the friendlies list is the broadest squad
        // picture (Zambia: 26 there vs 23 on the World Cup feed). If someone reorders the
        // list, squads across the app change silently — this makes that a conscious edit.
        #expect(NationalTeamFeed.all.first?.slug == "fifa.friendly.w")
    }
}
