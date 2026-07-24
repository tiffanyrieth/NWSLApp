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

    @Test func tierByAbsoluteScore() {
        // Even quartiles on the 0–100 scale: Fan 0–24 · Rising 25–49 · All-Star 50–74 · MVP 75–100.
        #expect(SuperfanTier.forScore(0) == .fan)
        #expect(SuperfanTier.forScore(24) == .fan)
        #expect(SuperfanTier.forScore(25) == .rising)     // lower bound inclusive
        #expect(SuperfanTier.forScore(49) == .rising)
        #expect(SuperfanTier.forScore(50) == .allStar)
        #expect(SuperfanTier.forScore(74) == .allStar)
        #expect(SuperfanTier.forScore(75) == .mvp)
        #expect(SuperfanTier.forScore(100) == .mvp)
    }

    @Test func tierNextChain() {
        #expect(SuperfanTier.fan.next == .rising)
        #expect(SuperfanTier.rising.next == .allStar)
        #expect(SuperfanTier.allStar.next == .mvp)
        #expect(SuperfanTier.mvp.next == nil)
    }

    @Test func tierProgressFillAndCaption() {
        // Score 62 → All-Star tier, 13 points to MVP... wait: 62 is All-Star (50–74), next = MVP (75).
        let p = TierProgress(score: 62)
        #expect(p.current == .allStar)
        #expect(p.pointsToNext == 13)                     // 75 − 62
        #expect(p.caption == "13 points to MVP")
        #expect(abs(p.fraction - Double(62 - 50) / Double(75 - 50)) < 0.0001)
        // MVP terminal: full bar, no "points to" line.
        let top = TierProgress(score: 88)
        #expect(top.current == .mvp)
        #expect(top.fraction == 1.0)
        #expect(top.pointsToNext == 0)
        #expect(top.caption == "MVP — you've reached the top")
        // Singular pluralization.
        #expect(TierProgress(score: 24).caption == "1 point to Rising")
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
