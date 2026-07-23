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

    /// The standing line renders at EVERY field size (the old ≥5-qualifiers gate is gone — owner ruling
    /// 2026-07-22: a first player has to see the shape of the feature). N=1 is the one special case:
    /// `rank/qualifying` is 1.0 there, so a percentile would read "Top 100% of 1 fans".
    @Test func standingTextAtEveryScale() {
        #expect(SuperfanStanding(rank: 1, qualifying: 1).standingText == "#1 of 1 fan")
        #expect(SuperfanStanding(rank: 1, qualifying: 2).standingText == "Top 50% of 2 fans")
        #expect(SuperfanStanding(rank: 1, qualifying: 4).standingText == "Top 25% of 4 fans")
        #expect(SuperfanStanding(rank: 12, qualifying: 100).standingText == "Top 12% of 100 fans")
    }

    /// The regression this guards: never render a percentile for a field of one, at any rank.
    @Test func singleFanNeverShowsAPercentile() {
        #expect(!SuperfanStanding(rank: 1, qualifying: 1).standingText.contains("%"))
        #expect(!SuperfanStanding(rank: 1, qualifying: 0).standingText.contains("%"))
    }
}
