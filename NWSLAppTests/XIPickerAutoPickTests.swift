//
//  XIPickerAutoPickTests.swift
//  NWSLAppTests
//
//  Auto-pick became POSITION-AWARE on 2026-07-28 (owner, after living with the old behaviour):
//  still random, but drawn from each slot's own band, so a squad with three keepers gives a
//  different one in goal each time you re-tap and never a striker.
//
//  ⚠️ WHAT'S WORTH PINNING isn't the happy path — it's the SHORT-BAND fallback. A random 5-3-2
//  against a squad carrying four defenders has to still produce eleven players, because auto-pick's
//  whole promise is a complete XI you can then tweak, and a half-filled grid can't be submitted at
//  all. And when it does backfill, a spare keeper must be the last resort rather than the first
//  thing that lands up front — which is the exact outcome this change exists to prevent.
//

import Foundation
import Testing
@testable import NWSLApp

struct XIPickerAutoPickTests {

    private func athlete(_ id: String, _ abbreviation: String) -> Athlete {
        Athlete(id: id, name: "Player \(id)", shortName: nil, jersey: nil,
                positionName: nil, positionAbbreviation: abbreviation,
                age: nil, displayHeight: nil, citizenship: nil)
    }

    /// A realistic squad: 3 keepers, 7 defenders, 7 midfielders, 5 forwards.
    private func squad() -> [Athlete] {
        (0..<3).map { athlete("gk\($0)", "G") }
            + (0..<7).map { athlete("df\($0)", "D") }
            + (0..<7).map { athlete("mf\($0)", "M") }
            + (0..<5).map { athlete("fw\($0)", "F") }
    }

    /// Built through the REAL `load()` path rather than a test-only setter, so the roster arrives
    /// exactly the way it does in the app.
    private func picker(roster: [Athlete], existing: XIPrediction? = nil) async -> XIPickerViewModel {
        let fixture = PredictionFixture(eventID: "e1", teamAbbreviation: "WAS",
                                        opponentAbbreviation: "UTA", isHome: true,
                                        kickoff: Date().addingTimeInterval(86_400))
        let vm = XIPickerViewModel(fixture: fixture, existing: existing, loadRoster: { roster })
        await vm.load()
        return vm
    }

    private func band(_ a: Athlete) -> PositionGroup {
        PositionGroup.from(abbreviation: a.positionAbbreviation)
    }

    // MARK: - The change itself

    @Test func everySlotGetsAPlayerFromItsOwnBand() async {
        let vm = await picker(roster: squad())
        // Repeat: the formation is randomized each call, so one run only exercises one shape.
        for _ in 0..<50 {
            vm.autoPick()
            #expect(vm.isComplete)
            for slot in vm.formation.slots {
                let picked = vm.athlete(inSlot: slot.index)
                #expect(picked != nil)
                if let picked { #expect(band(picked) == slot.group) }
            }
        }
    }

    @Test func aKeeperNeverLandsOutfieldWhenTheSquadIsHealthy() async {
        let vm = await picker(roster: squad())
        for _ in 0..<50 {
            vm.autoPick()
            for slot in vm.formation.slots where slot.group != .gk {
                if let picked = vm.athlete(inSlot: slot.index) { #expect(band(picked) != .gk) }
            }
        }
    }

    /// The point of "still random": re-tapping should reshuffle within the band. With three keepers
    /// and 50 rolls, always getting the same one would mean the randomness was lost.
    @Test func reTappingVariesTheKeeperAcrossASquadWithThree() async {
        let vm = await picker(roster: squad())
        var keepers = Set<String>()
        for _ in 0..<50 {
            vm.autoPick()
            if let gkSlot = vm.formation.slots.first(where: { $0.group == .gk }),
               let picked = vm.athlete(inSlot: gkSlot.index) {
                keepers.insert(picked.id)
            }
        }
        #expect(keepers.count > 1)
    }

    @Test func noPlayerIsAssignedToTwoSlots() async {
        let vm = await picker(roster: squad())
        for _ in 0..<50 {
            vm.autoPick()
            let ids = vm.formation.slots.compactMap { vm.athlete(inSlot: $0.index)?.id }
            #expect(Set(ids).count == ids.count)
        }
    }

    // MARK: - The short-band fallback

    /// Four defenders, but 5-3-2 and 5-4-1 exist in the menu. The XI must still be complete.
    @Test func aShortBandStillYieldsElevenPlayers() async {
        let thin = (0..<3).map { athlete("gk\($0)", "G") }
            + (0..<4).map { athlete("df\($0)", "D") }
            + (0..<8).map { athlete("mf\($0)", "M") }
            + (0..<4).map { athlete("fw\($0)", "F") }
        let vm = await picker(roster: thin)
        for _ in 0..<80 {
            vm.autoPick()
            #expect(vm.isComplete)
            let ids = vm.formation.slots.compactMap { vm.athlete(inSlot: $0.index)?.id }
            #expect(Set(ids).count == 11)
        }
    }

    /// When backfilling, outfield slots must exhaust every non-keeper before reaching for a spare
    /// keeper. Here there are exactly 11 outfielders and 3 keepers, so a correct implementation
    /// never needs a keeper outfield even though a 5-back formation runs the defence short.
    @Test func backfillPrefersOutfieldersOverSpareKeepers() async {
        let thin = (0..<3).map { athlete("gk\($0)", "G") }
            + (0..<3).map { athlete("df\($0)", "D") }
            + (0..<5).map { athlete("mf\($0)", "M") }
            + (0..<3).map { athlete("fw\($0)", "F") }
        let vm = await picker(roster: thin)
        for _ in 0..<80 {
            vm.autoPick()
            for slot in vm.formation.slots where slot.group != .gk {
                if let picked = vm.athlete(inSlot: slot.index) { #expect(band(picked) != .gk) }
            }
        }
    }

    /// A squad too small to field an XI fills what it can rather than crashing — the same
    /// degradation the position-blind version had.
    @Test func anUnderSizedSquadFillsWhatItCanWithoutCrashing() async {
        let tiny = [athlete("gk0", "G"), athlete("df0", "D"), athlete("fw0", "F")]
        let vm = await picker(roster: tiny)
        vm.autoPick()
        #expect(!vm.isComplete)
        #expect(vm.assignedCount == 3)
    }

    @Test func anEmptyRosterIsANoOp() async {
        let vm = await picker(roster: [])
        vm.autoPick()
        #expect(vm.assignedCount == 0)
    }

    /// Position NAME is the documented fallback when ESPN omits the abbreviation.
    @Test func bandingFallsBackToThePositionNameWhenTheAbbreviationIsMissing() async {
        let named = [Athlete(id: "gk0", name: "K", shortName: nil, jersey: nil,
                             positionName: "Goalkeeper", positionAbbreviation: nil,
                             age: nil, displayHeight: nil, citizenship: nil)]
            + (0..<4).map { Athlete(id: "df\($0)", name: "D", shortName: nil, jersey: nil,
                                    positionName: "Defender", positionAbbreviation: nil,
                                    age: nil, displayHeight: nil, citizenship: nil) }
            + (0..<4).map { Athlete(id: "mf\($0)", name: "M", shortName: nil, jersey: nil,
                                    positionName: "Midfielder", positionAbbreviation: nil,
                                    age: nil, displayHeight: nil, citizenship: nil) }
            + (0..<4).map { Athlete(id: "fw\($0)", name: "F", shortName: nil, jersey: nil,
                                    positionName: "Forward", positionAbbreviation: nil,
                                    age: nil, displayHeight: nil, citizenship: nil) }
        let vm = await picker(roster: named)
        vm.autoPick()
        if let gkSlot = vm.formation.slots.first(where: { $0.group == .gk }) {
            #expect(vm.athlete(inSlot: gkSlot.index)?.id == "gk0")
        }
    }

    // MARK: - Read-only

    @Test func aSubmittedPredictionIgnoresAutoPick() async {
        let submitted = XIPrediction(fixtureID: "e1-WAS", eventID: "e1", teamAbbreviation: "WAS",
                                     state: .submitted)
        let vm = await picker(roster: squad(), existing: submitted)
        vm.autoPick()
        #expect(vm.assignedCount == 0)
    }
}
