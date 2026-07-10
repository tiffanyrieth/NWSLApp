//
//  LeaderboardRankingTests.swift
//  NWSLAppTests
//
//  Pure-logic checks for the "top-100 + your rank" placement rule shared by the Fan
//  Zone leaderboards. The honesty guarantee (a below-cap player is NEVER shown a
//  flattering ~101 rank) lives here — see LeaderboardRanking.swift.
//

import Foundation
import Testing
@testable import NWSLApp

struct LeaderboardRankingTests {
    typealias R = LeaderboardRanking

    @Test func signedOutHasNoYouRow() {
        #expect(R.placement(trueRank: nil, cappedRivalCount: 100) == .none)
    }

    @Test func withinWindowSplicesInline() {
        // Rank 50 of a full board → inline at slot 49 (0-based).
        #expect(R.placement(trueRank: 50, cappedRivalCount: 100) == .inline(49))
        // Rank 1 → the very top slot.
        #expect(R.placement(trueRank: 1, cappedRivalCount: 100) == .inline(0))
        // Exactly at the cap is still inside.
        #expect(R.placement(trueRank: R.visibleLimit, cappedRivalCount: 100) == .inline(R.visibleLimit - 1))
    }

    @Test func pastWindowSplicesBelowFoldWithTrueRank() {
        // The whole point: 412th of 800 shows "#412", not a truncated ~101.
        #expect(R.placement(trueRank: 412, cappedRivalCount: 100) == .belowFold(412))
        #expect(R.placement(trueRank: 101, cappedRivalCount: 100) == .belowFold(101))
    }

    @Test func smallBoardClampsSlotToRivalsOnHand() {
        // A 6-player board (5 rivals fetched): rank 6 clamps to slot 5 (append at end),
        // never indexing past the rivals we actually have.
        #expect(R.placement(trueRank: 6, cappedRivalCount: 5) == .inline(5))
        #expect(R.placement(trueRank: 3, cappedRivalCount: 5) == .inline(2))
    }
}
