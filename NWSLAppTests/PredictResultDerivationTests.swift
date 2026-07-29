//
//  PredictResultDerivationTests.swift
//  NWSLAppTests
//
//  The results screen grades the REAL XI against the user's prediction (fork B, owner call
//  2026-07-28): each actual starter is called or missed, and picks who sat are busts.
//
//  ⚠️ THE INVARIANT THESE TESTS EXIST FOR: the ✓ count the user READS must equal the points the
//  user is RANKED on. Set-wise identity: "starters you called" and "your picks who started" are the
//  same set counted from either side, so startersCalled == PredictionScoring.correctPlayers for
//  every input. The agreement test runs both implementations over generated pairs.
//

import Foundation
import Testing
@testable import NWSLApp

struct PredictResultDerivationTests {

    /// A 4-3-3 answer key with ids "a0"…"a10": a0 GK, a1–a4 DEF, a5–a7 MID, a8–a10 FWD.
    private func actual4333() -> ActualResult {
        let groups: [PositionGroup] = [.gk] + Array(repeating: .def, count: 4)
            + Array(repeating: .mid, count: 3) + Array(repeating: .fwd, count: 3)
        let starters = groups.enumerated().map {
            ActualResult.Starter(athleteID: "a\($0.offset)", group: $0.element)
        }
        return ActualResult(formation: "4-3-3", starters: starters, homeScore: 2, awayScore: 1)
    }

    private func prediction(slots: [Int: String], formation: String = "4-3-3") -> XIPrediction {
        XIPrediction(fixtureID: "e1-WAS", eventID: "e1", teamAbbreviation: "WAS",
                     formation: formation, slots: slots,
                     homeScoreGuess: 2, awayScoreGuess: 1, state: .submitted)
    }

    private var perfectSlots: [Int: String] {
        Dictionary(uniqueKeysWithValues: (0...10).map { ($0, "a\($0)") })
    }

    private func names(_ ids: [String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: ids.map { ($0, "Player \($0)") })
    }

    // MARK: - Grading the real XI

    @Test func aPerfectPredictionCallsEveryStarter() {
        let results = PredictResultDerivation.starterResults(for: prediction(slots: perfectSlots),
                                                             against: actual4333(),
                                                             names: names((0...10).map { "a\($0)" }))
        #expect(results.count == 11)
        #expect(results.allSatisfy { $0.called })
        #expect(PredictResultDerivation.startersCalled(results) == 11)
    }

    @Test func anUnpickedStarterIsMissedAndTheBenchPickIsABust() {
        var slots = perfectSlots
        slots[10] = "bench1"
        let p = prediction(slots: slots)
        let allNames = names((0...10).map { "a\($0)" } + ["bench1"])
        let results = PredictResultDerivation.starterResults(for: p, against: actual4333(), names: allNames)
        let busts = PredictResultDerivation.busts(for: p, against: actual4333(), names: allNames)

        #expect(results.first { $0.athleteID == "a10" }?.called == false)
        #expect(PredictResultDerivation.startersCalled(results) == 10)
        #expect(busts.map(\.athleteID) == ["bench1"])
    }

    /// ⚠️ Set-wise: a player you slotted in the WRONG band is still CALLED — she counts wherever
    /// you put her, exactly like the scorer's hit test.
    @Test func aPlayerSlottedInAnotherBandIsStillCalled() {
        var slots = perfectSlots
        slots[1] = "a5"      // midfielder in a defensive slot
        slots[5] = "a1"      // defender in a midfield slot
        let results = PredictResultDerivation.starterResults(for: prediction(slots: slots),
                                                             against: actual4333(),
                                                             names: names((0...10).map { "a\($0)" }))
        #expect(results.allSatisfy { $0.called })
        #expect(PredictResultDerivation.busts(for: prediction(slots: slots),
                                              against: actual4333(),
                                              names: names((0...10).map { "a\($0)" })).isEmpty)
    }

    /// Starters carry the band they ACTUALLY played — the pitch rows come from the real lineup.
    @Test func startersAreGroupedByTheirRealBand() {
        let results = PredictResultDerivation.starterResults(for: prediction(slots: perfectSlots),
                                                             against: actual4333(),
                                                             names: names((0...10).map { "a\($0)" }))
        let tallies = PredictResultDerivation.bandTallies(results)
        #expect(tallies.map(\.group) == [.gk, .def, .mid, .fwd])
        #expect(tallies.map(\.total) == [1, 4, 3, 3])
    }

    @Test func bandTalliesCountCalledPerLine() {
        var slots = perfectSlots
        slots[1] = "bench1"   // one defender missed
        let results = PredictResultDerivation.starterResults(
            for: prediction(slots: slots), against: actual4333(),
            names: names((0...10).map { "a\($0)" } + ["bench1"]))
        let defense = PredictResultDerivation.bandTallies(results).first { $0.group == .def }
        #expect(defense?.total == 4)
        #expect(defense?.called == 3)
    }

    // MARK: - The anti-drift invariant

    @Test func calledCountAlwaysAgreesWithTheScorer() {
        let actual = actual4333()
        let pool = (0...10).map { "a\($0)" } + ["b0", "b1", "b2", "b3"]
        var generator = SystemRandomNumberGenerator()

        for _ in 0..<200 {
            var slots: [Int: String] = [:]
            var used = Set<String>()
            for index in 0...10 {
                var candidate = pool.randomElement(using: &generator)!
                while used.contains(candidate) { candidate = pool.randomElement(using: &generator)! }
                used.insert(candidate)
                slots[index] = candidate
            }
            let p = prediction(slots: slots)
            let score = PredictionScoring.score(p, against: actual)
            let results = PredictResultDerivation.starterResults(for: p, against: actual, names: names(pool))
            let busts = PredictResultDerivation.busts(for: p, against: actual, names: names(pool))

            #expect(PredictResultDerivation.startersCalled(results) == score.correctPlayers)
            // Every pick is either a called starter or a bust — nothing vanishes.
            #expect(PredictResultDerivation.startersCalled(results) + busts.count == 11)
        }
    }

    // MARK: - Standouts

    @Test func standoutsPickTheLowestOwnedCallAndTheHighestOwnedMiss() {
        var slots = perfectSlots
        slots[10] = "bench1"                      // a10 becomes the missed starter
        var counts: [PredictCommunity.Pick: Int] = [:]
        for index in 0...9 { counts[.init(playerID: "a\(index)", slot: index)] = 60 }
        counts[.init(playerID: "a8", slot: 8)] = 14      // the gutsy call that came off
        counts[.init(playerID: "bench1", slot: 10)] = 20
        counts[.init(playerID: "a10", slot: 10)] = 83    // the name everyone else had
        let community = PredictCommunity(
            eventID: "e1", team: "WAS", week: 12, revealed: true, closesAt: nil, submissions: 100,
            counts: counts)
        let ids = (0...10).map { "a\($0)" } + ["bench1"]
        let results = PredictResultDerivation.starterResults(for: prediction(slots: slots),
                                                             against: actual4333(),
                                                             names: names(ids), community: community)
        let standouts = PredictResultDerivation.standouts(starters: results)
        #expect(standouts.hit?.athleteID == "a8")
        #expect(standouts.upset?.athleteID == "a10")
    }

    /// ⚠️ The hit ceiling is a THIRD, not half (owner): a steady first-choice keeper at 40%+ must
    /// never be praised as gutsy just for being your least-owned correct pick.
    @Test func aSteadilyOwnedPickIsNeverAGutsyCall() {
        let counts = Dictionary(uniqueKeysWithValues: (0...10).map {
            (PredictCommunity.Pick(playerID: "a\($0)", slot: $0), $0 == 0 ? 40 : 90)
        })
        let community = PredictCommunity(
            eventID: "e1", team: "WAS", week: 12, revealed: true, closesAt: nil, submissions: 100,
            counts: counts)
        let results = PredictResultDerivation.starterResults(for: prediction(slots: perfectSlots),
                                                             against: actual4333(),
                                                             names: names((0...10).map { "a\($0)" }),
                                                             community: community)
        #expect(PredictResultDerivation.standouts(starters: results).hit == nil)
    }

    @Test func standoutsAreAbsentWithoutCommunityData() {
        let results = PredictResultDerivation.starterResults(for: prediction(slots: perfectSlots),
                                                             against: actual4333(),
                                                             names: names((0...10).map { "a\($0)" }))
        let standouts = PredictResultDerivation.standouts(starters: results)
        #expect(standouts.hit == nil)
        #expect(standouts.upset == nil)
    }

    /// A 0% share on someone you called means the distribution is partial, never a fact.
    @Test func aStarterMissingFromTheDistributionIsNotAStandout() {
        let community = PredictCommunity(
            eventID: "e1", team: "WAS", week: 12, revealed: true, closesAt: nil, submissions: 100,
            counts: [.init(playerID: "a0", slot: 0): 90])
        let results = PredictResultDerivation.starterResults(for: prediction(slots: perfectSlots),
                                                             against: actual4333(),
                                                             names: names((0...10).map { "a\($0)" }),
                                                             community: community)
        #expect(PredictResultDerivation.standouts(starters: results).hit == nil)
    }
}
