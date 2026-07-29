//
//  PredictResultDerivationTests.swift
//  NWSLAppTests
//
//  The redesigned results screen re-derives per-pick detail (who started, who started in a different
//  BAND) from the re-fetched lineup, because `PredictionScore` persists only aggregate counts. That
//  means two pieces of code now compare a prediction against the same answer key:
//  `PredictionScoring.score`, which produces the points the user is RANKED on, and
//  `PredictResultDerivation`, which produces the ✓/✗ the user READS.
//
//  ⚠️ THE INVARIANT THESE TESTS EXIST FOR: those two must always agree. If they drift, the pitch
//  shows nine green nodes directly above a breakdown row reading "Correct players 8/11" — the screen
//  contradicting itself, which is worse than either number being wrong alone. The agreement test
//  below runs both implementations over many generated prediction/answer-key pairs rather than
//  trusting inspection to keep them in step.
//

import Foundation
import Testing
@testable import NWSLApp

struct PredictResultDerivationTests {

    // MARK: - Fixtures

    /// A 4-3-3 answer key with ids "a0"…"a10": a0 GK, a1–a4 DEF, a5–a7 MID, a8–a10 FWD — matching
    /// the 4-3-3 slot bands exactly.
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

    // MARK: - The three states

    @Test func aPerfectXIIsAllInBand() {
        let picks = PredictResultDerivation.picks(for: prediction(slots: perfectSlots),
                                                  against: actual4333(),
                                                  names: names((0...10).map { "a\($0)" }))
        #expect(picks.count == 11)
        #expect(picks.allSatisfy { $0.state == .startedInBand })
        #expect(PredictResultDerivation.startersCalled(picks) == 11)
    }

    @Test func aPickWhoDidNotStartIsTheOnlyStateWorthNoPoints() {
        var slots = perfectSlots
        slots[10] = "bench1"                      // someone who isn't in the XI at all
        let picks = PredictResultDerivation.picks(for: prediction(slots: slots),
                                                  against: actual4333(),
                                                  names: names((0...10).map { "a\($0)" } + ["bench1"]))
        let missed = picks.filter { $0.state == .didNotStart }
        #expect(missed.count == 1)
        #expect(missed.first?.athleteID == "bench1")
        #expect(PredictResultDerivation.startersCalled(picks) == 10)
    }

    /// The state the redesign exists to surface: she played, so she banks the player points, but in
    /// a different band — so she is a HIT rendered amber, never a miss rendered red.
    @Test func aPlayerWhoStartedInAnotherBandIsStillAHit() {
        var slots = perfectSlots
        // Put a midfielder (a5) in a defensive slot and the defender (a1) in the midfield slot.
        slots[1] = "a5"
        slots[5] = "a1"
        let picks = PredictResultDerivation.picks(for: prediction(slots: slots),
                                                  against: actual4333(),
                                                  names: names((0...10).map { "a\($0)" }))
        // Both are still starters — the hit test is set-wise.
        #expect(PredictResultDerivation.startersCalled(picks) == 11)
        let offBand = picks.filter {
            if case .startedOffBand = $0.state { return true }
            return false
        }
        #expect(offBand.count == 2)
        // And the copy names the band she ACTUALLY played, not the one you chose.
        let slotOne = picks.first { $0.slot.index == 1 }
        #expect(slotOne?.state == .startedOffBand(actual: .mid))
    }

    /// ⚠️ BAND-level, not slot-level. Left-back vs centre-back is FULLY correct — the scorer never
    /// compares slots, so the UI must not imply it does.
    @Test func swappingTwoPlayersWithinTheSameBandIsFullyCorrect() {
        var slots = perfectSlots
        slots[1] = "a2"      // two defenders swapped between defensive slots
        slots[2] = "a1"
        let picks = PredictResultDerivation.picks(for: prediction(slots: slots),
                                                  against: actual4333(),
                                                  names: names((0...10).map { "a\($0)" }))
        #expect(picks.allSatisfy { $0.state == .startedInBand })
    }

    // MARK: - The anti-drift invariant

    /// Over many randomized predictions, the derived per-pick states must reproduce EXACTLY the
    /// aggregate counts the scorer independently computes. This is the test that stops the pitch and
    /// the breakdown table from ever disagreeing.
    @Test func derivedStatesAlwaysAgreeWithTheScorer() {
        let actual = actual4333()
        let pool = (0...10).map { "a\($0)" } + ["b0", "b1", "b2", "b3"]   // 11 starters + 4 non-starters
        var generator = SystemRandomNumberGenerator()

        for _ in 0..<200 {
            var slots: [Int: String] = [:]
            var used = Set<String>()
            for index in 0...10 {
                // A distinct player per slot, exactly like the picker enforces.
                var candidate = pool.randomElement(using: &generator)!
                while used.contains(candidate) { candidate = pool.randomElement(using: &generator)! }
                used.insert(candidate)
                slots[index] = candidate
            }
            let p = prediction(slots: slots)
            let score = PredictionScoring.score(p, against: actual)
            let picks = PredictResultDerivation.picks(for: p, against: actual, names: names(pool))

            #expect(PredictResultDerivation.startersCalled(picks) == score.correctPlayers)
            let inBand = picks.filter { $0.state == .startedInBand }.count
            #expect(inBand == score.correctPositions)
        }
    }

    // MARK: - Missed starters

    @Test func missedStartersAreActualStartersPickedNowhere() {
        var slots = perfectSlots
        slots[9] = "bench1"
        slots[10] = "bench2"
        let picks = names((0...10).map { "a\($0)" } + ["bench1", "bench2"])
        let missed = PredictResultDerivation.missedStarters(for: prediction(slots: slots),
                                                            against: actual4333(),
                                                            names: picks)
        #expect(Set(missed.map(\.athleteID)) == ["a9", "a10"])
    }

    /// A player you moved to a different slot is a HIT, so she must never appear in the missed list —
    /// that would double-count her as both called and missed.
    @Test func aRepositionedPlayerIsNeverListedAsMissed() {
        var slots = perfectSlots
        slots[1] = "a5"
        slots[5] = "a1"
        let missed = PredictResultDerivation.missedStarters(for: prediction(slots: slots),
                                                            against: actual4333(),
                                                            names: names((0...10).map { "a\($0)" }))
        #expect(missed.isEmpty)
    }

    // MARK: - Standouts

    @Test func standoutsPickTheLowestOwnedHitAndTheHighestOwnedMiss() {
        var slots = perfectSlots
        slots[10] = "bench1"                      // a10 becomes a missed starter
        // A realistic distribution: every player you picked is counted (your own submission is in
        // there), plus the starter you left out.
        var counts: [PredictCommunity.Pick: Int] = [:]
        for index in 0...9 { counts[.init(playerID: "a\(index)", slot: index)] = 90 }
        counts[.init(playerID: "a8", slot: 8)] = 14      // your gutsiest call that came off
        counts[.init(playerID: "bench1", slot: 10)] = 20
        counts[.init(playerID: "a10", slot: 10)] = 83    // the obvious name you left out
        let community = PredictCommunity(
            eventID: "e1", team: "WAS", week: 12, revealed: true, closesAt: nil, submissions: 100,
            counts: counts)
        let ids = (0...10).map { "a\($0)" } + ["bench1"]
        let picks = PredictResultDerivation.picks(for: prediction(slots: slots), against: actual4333(),
                                                  names: names(ids), community: community)
        let missed = PredictResultDerivation.missedStarters(for: prediction(slots: slots),
                                                            against: actual4333(),
                                                            names: names(ids), community: community)
        let standouts = PredictResultDerivation.standouts(picks: picks, missed: missed)
        #expect(standouts.hit?.athleteID == "a8")
        #expect(standouts.miss?.athleteID == "a10")
    }

    /// With no community data there are no shares, so there is no "only 14% had her" to state.
    /// Both cards must be absent rather than shown with an invented number.
    @Test func standoutsAreAbsentWithoutCommunityData() {
        let picks = PredictResultDerivation.picks(for: prediction(slots: perfectSlots),
                                                  against: actual4333(),
                                                  names: names((0...10).map { "a\($0)" }))
        let standouts = PredictResultDerivation.standouts(picks: picks, missed: [])
        #expect(standouts.hit == nil)
        #expect(standouts.miss == nil)
    }

    /// A pick with a 0% share is impossible if the aggregate counted your own submission, so it's
    /// partial data — and must not be presented as the boldest call of the match.
    @Test func aPickMissingFromTheDistributionIsNotAStandout() {
        let community = PredictCommunity(
            eventID: "e1", team: "WAS", week: 12, revealed: true, closesAt: nil, submissions: 100,
            counts: [.init(playerID: "a0", slot: 0): 90])   // every other pick absent
        let picks = PredictResultDerivation.picks(for: prediction(slots: perfectSlots),
                                                  against: actual4333(),
                                                  names: names((0...10).map { "a\($0)" }),
                                                  community: community)
        #expect(PredictResultDerivation.standouts(picks: picks, missed: []).hit == nil)
    }

    /// A pick everyone made isn't a standout — it's a formality.
    @Test func aUniversallyOwnedHitIsNotAStandout() {
        let community = PredictCommunity(
            eventID: "e1", team: "WAS", week: 12, revealed: true, closesAt: nil, submissions: 100,
            counts: Dictionary(uniqueKeysWithValues: (0...10).map {
                (PredictCommunity.Pick(playerID: "a\($0)", slot: $0), 98)
            }))
        let picks = PredictResultDerivation.picks(for: prediction(slots: perfectSlots),
                                                  against: actual4333(),
                                                  names: names((0...10).map { "a\($0)" }),
                                                  community: community)
        #expect(PredictResultDerivation.standouts(picks: picks, missed: []).hit == nil)
    }

    // MARK: - Robustness

    @Test func anUnparseableFormationYieldsNoPicksRatherThanCrashing() {
        let picks = PredictResultDerivation.picks(for: prediction(slots: perfectSlots, formation: "nonsense"),
                                                  against: actual4333(),
                                                  names: names((0...10).map { "a\($0)" }))
        #expect(picks.isEmpty)
    }

    /// A five-row formation must derive cleanly — 4-2-3-1 and 4-1-4-1 are in the picker menu, and
    /// the pitch lays out rows from the formation rather than four fixed bands.
    @Test func fiveRowFormationsDeriveAllElevenPicks() {
        let slots = Dictionary(uniqueKeysWithValues: (0...10).map { ($0, "a\($0)") })
        let picks = PredictResultDerivation.picks(for: prediction(slots: slots, formation: "4-2-3-1"),
                                                  against: actual4333(),
                                                  names: names((0...10).map { "a\($0)" }))
        #expect(picks.count == 11)
        #expect(PredictResultDerivation.startersCalled(picks) == 11)
    }

    @Test func bandTalliesCountStartersPerLine() {
        var slots = perfectSlots
        slots[1] = "bench1"
        let tallies = PredictResultDerivation.bandTallies(
            PredictResultDerivation.picks(for: prediction(slots: slots), against: actual4333(),
                                          names: names((0...10).map { "a\($0)" } + ["bench1"])))
        let defense = tallies.first { $0.group == .def }
        #expect(defense?.total == 4)
        #expect(defense?.started == 3)
    }
}
