//
//  FormationLayoutTests.swift
//  NWSLAppTests
//
//  Guards FormationPitchView.layout against the 4-2-3-1 → 4-5-1 regression:
//  the row structure must come from the formation string so the two holding
//  mids and the three attacking mids sit on separate lines — even when ESPN
//  sends generic "M" abbreviations for every midfielder.
//

import Foundation
import Testing
@testable import NWSLApp

struct FormationLayoutTests {

    private func player(_ position: String, place: Int) -> MatchPlayer {
        let json = """
        {"athlete":{"id":"\(place)"},"jersey":"\(place)",
         "position":{"abbreviation":"\(position)"},"starter":true,
         "formationPlace":"\(place)"}
        """
        return try! JSONDecoder().decode(MatchPlayer.self, from: Data(json.utf8))
    }

    /// Row sizes from defence (bottom, largest screen-y) → attack (top), with the
    /// GK as the first (bottom-most) group.
    private func rowSizes(_ placed: [FormationPitchView.PlacedPlayer]) -> [Int] {
        let groups = Dictionary(grouping: placed) { (($0.point.y * 1000).rounded()) }
        return groups.keys.sorted(by: >).map { groups[$0]!.count }
    }

    @Test func specificAbbreviationsYield4231() {
        // Realistic WAS-style 4-2-3-1.
        let players = [
            player("G", place: 1),
            player("RB", place: 2), player("LB", place: 3),
            player("CD-R", place: 5), player("CD-L", place: 6),
            player("LM", place: 4), player("RM", place: 8),
            player("AM-L", place: 11), player("AM", place: 10), player("AM-R", place: 7),
            player("F", place: 9),
        ]
        let placed = FormationPitchView.layout(formation: "4-2-3-1", players: players)
        #expect(placed.count == 11)
        #expect(rowSizes(placed) == [1, 4, 2, 3, 1])   // GK, def, dm, am, fwd
    }

    @Test func genericMidfielderAbbreviationsStillYield4231() {
        // The bug case: every midfielder is a generic "M" — abbreviation alone
        // would pile all 5 on one line. The formation string must split them 2/3.
        let players = [
            player("G", place: 1),
            player("D", place: 2), player("D", place: 3), player("D", place: 4), player("D", place: 5),
            player("M", place: 6), player("M", place: 7),
            player("M", place: 8), player("M", place: 9), player("M", place: 10),
            player("F", place: 11),
        ]
        let placed = FormationPitchView.layout(formation: "4-2-3-1", players: players)
        #expect(rowSizes(placed) == [1, 4, 2, 3, 1])
    }

    @Test func fourThreeThreeYields433() {
        let players = [
            player("G", place: 1),
            player("RB", place: 2), player("CB", place: 3), player("CB", place: 4), player("LB", place: 5),
            player("CM", place: 6), player("CM", place: 7), player("CM", place: 8),
            player("RW", place: 9), player("ST", place: 10), player("LW", place: 11),
        ]
        let placed = FormationPitchView.layout(formation: "4-3-3", players: players)
        #expect(rowSizes(placed) == [1, 4, 3, 3])
    }
}
