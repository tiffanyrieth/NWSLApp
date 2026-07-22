//
//  SuperfanStatsTests.swift
//  NWSLAppTests
//
//  Superfan tier thresholds + the honest low-scale gate. Pure — no network (the combined-total math is
//  covered by GameCenterIDsTests; the count-based rank is exercised live via Supabase).
//

import Testing
@testable import NWSLApp

struct SuperfanStatsTests {

    @Test func tierByTopFraction() {
        // Fan → Rising (top 50%) → All-Star (top 20%) → MVP (top 5%), thresholds inclusive.
        #expect(SuperfanStanding(rank: 1, qualifying: 100).tier == .mvp)      // top 1%
        #expect(SuperfanStanding(rank: 5, qualifying: 100).tier == .mvp)      // exactly top 5%
        #expect(SuperfanStanding(rank: 6, qualifying: 100).tier == .allStar)  // 6%
        #expect(SuperfanStanding(rank: 20, qualifying: 100).tier == .allStar) // exactly top 20%
        #expect(SuperfanStanding(rank: 21, qualifying: 100).tier == .rising)  // 21%
        #expect(SuperfanStanding(rank: 50, qualifying: 100).tier == .rising)  // exactly top 50%
        #expect(SuperfanStanding(rank: 51, qualifying: 100).tier == .fan)     // 51%
    }

    @Test func topPercentNeverZero() {
        #expect(SuperfanStanding(rank: 12, qualifying: 100).topPercent == 12)
        // Being #1 of many is "Top 1%", never "Top 0%".
        #expect(SuperfanStanding(rank: 1, qualifying: 500).topPercent == 1)
    }

    @Test func meaningfulOnlyWithEnoughQualifiers() {
        #expect(SuperfanStanding(rank: 1, qualifying: 5).isMeaningful)   // at the threshold
        #expect(!SuperfanStanding(rank: 1, qualifying: 4).isMeaningful)  // too few fans → building state
        #expect(!SuperfanStanding(rank: 1, qualifying: 3).isMeaningful)
    }
}
