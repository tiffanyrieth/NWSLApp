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

/// National-team squad feed selection (bug found on TestFlight build 31, 2026-07-31).
///
/// The first rule took the broadest squad — friendlies first. Several feeds publish a squad with
/// NO shirt numbers, and friendlies is one: USA via `fifa.friendly.w` = 26 players / **0 numbers**,
/// while `fifa.shebelieves` = 26 / 25. So the USWNT roster shipped with every number missing — and
/// "who is number 7" is the whole reason a fan opens that page in a stadium.
struct NationalSquadNumbersTests {
    private let service = ESPNService()

    private func squad(_ jerseys: [String?]) -> ClubSquad {
        ClubSquad(
            athletes: jerseys.enumerated().map { i, j in
                Athlete(id: "\(i)", name: "P \(i)", shortName: nil, jersey: j,
                        positionName: "Forward", positionAbbreviation: "F",
                        age: nil, displayHeight: nil, citizenship: nil)
            },
            colorHex: nil, standingSummary: nil, record: nil, cachedAsOf: nil)
    }

    @Test func aSquadWithNoNumbersIsRejectedAsThePreferredSource() {
        // The exact USA/friendlies shape: real names, zero numbers.
        #expect(service.squadHasNumbers(squad(Array(repeating: nil, count: 26))) == false)
        #expect(service.squadHasNumbers(squad(Array(repeating: "", count: 26))) == false)
    }

    @Test func aSquadWithNumbersIsPreferred() {
        #expect(service.squadHasNumbers(squad(["7", "9", "11"])) == true)
    }

    @Test func oneMissingNumberDoesNotDisqualifyARealSquad() {
        // A just-called-up player may have no number yet — requiring ALL of them would reject a
        // good feed (SheBelieves: 26 players, 25 numbered) over a single blank.
        #expect(service.squadHasNumbers(squad(["7", nil, "11", nil])) == true)
    }

    @Test func anEmptySquadHasNoNumbers() {
        #expect(service.squadHasNumbers(squad([])) == false)
    }
}

/// Jersey back-fill (2026-07-31, second pass). "First feed with ANY number" was still wrong: the
/// friendlies feed carries ~no numbers for anyone (USA 0/26, China 5/26, Japan 5/26), so a squad with
/// 5 numbered players satisfied "has numbers" and stopped the search while a fully-numbered feed sat
/// two entries down (Japan's World Cup roster: 23/23). Now a squad must be WELL numbered to stop the
/// search; a sparse one keeps going and has its blanks filled per-player.
struct NationalSquadBackfillTests {
    private let service = ESPNService()

    private func squad(_ pairs: [(String, String?)]) -> ClubSquad {
        ClubSquad(
            athletes: pairs.map { id, j in
                Athlete(id: id, name: "P \(id)", shortName: nil, jersey: j,
                        positionName: "Forward", positionAbbreviation: "F",
                        age: nil, displayHeight: nil, citizenship: nil)
            },
            colorHex: nil, standingSummary: nil, record: nil, cachedAsOf: nil)
    }

    @Test func fiveOfTwentySixStillCountsAsHavingNumbers() {
        // Why the first fix wasn't enough: this passes `squadHasNumbers` and used to end the search.
        var pairs: [(String, String?)] = (0..<5).map { ("\($0)", "\($0 + 1)") }
        pairs += (5..<26).map { ("\($0)", nil) }
        #expect(service.squadHasNumbers(squad(pairs)) == true)
    }

    @Test func backfillFillsOnlyTheBlanks_andNeverOverwritesAnExistingNumber() {
        // The chosen squad's own numbers are the national-team numbers — another feed must not
        // replace them (that's how a club number would leak into a national-team page).
        let chosen = squad([("a", "7"), ("b", nil), ("c", nil)])
        let other = squad([("a", "99"), ("b", "11")])
        let out = service.backfillJerseysForTesting(into: chosen, from: [other])
        #expect(out.athletes.first { $0.id == "a" }?.jersey == "7")   // kept, not overwritten
        #expect(out.athletes.first { $0.id == "b" }?.jersey == "11")  // filled
        #expect(out.athletes.first { $0.id == "c" }?.jersey == nil)   // no source, stays honest
    }

    @Test func backfillNeverAddsOrRemovesPlayers() {
        // Membership comes from ONE feed — unioning player lists was measured and is wrong
        // (USA 26 → 64, i.e. everyone who ever appeared, not a squad).
        let chosen = squad([("a", nil), ("b", nil)])
        let other = squad([("a", "5"), ("z", "9")])   // "z" is not on the chosen squad
        let out = service.backfillJerseysForTesting(into: chosen, from: [other])
        #expect(out.athletes.count == 2)
        #expect(out.athletes.contains { $0.id == "z" } == false)
    }

    @Test func aFullyNumberedSquadIsReturnedUntouched() {
        let chosen = squad([("a", "1"), ("b", "2")])
        let out = service.backfillJerseysForTesting(into: chosen, from: [squad([("a", "99")])])
        #expect(out.athletes.map(\.jersey) == ["1", "2"])
    }
}
