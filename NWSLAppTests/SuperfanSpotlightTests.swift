//
//  SuperfanSpotlightTests.swift
//  NWSLAppTests
//
//  The rotating "what we noticed" spotlight (SuperfanSpotlight) — pure, no I/O. Verifies the pool is only
//  ever built from REAL signals (no fabrication), always has SOMETHING to say (the playful floor), and
//  rotates deterministically.
//

import Foundation
import Testing
@testable import NWSLApp

struct SuperfanSpotlightTests {

    private func input(_ counts: SuperfanCounts, playersLearned: Int = 0,
                       best: Int? = nil, achievement: String? = nil) -> SuperfanSpotlight.Input {
        let bd = SuperfanScoring.breakdown(counts: counts)
        return .init(total: bd.total, breakdown: bd, playersLearned: playersLearned,
                     bestPredictStarters: best, recentAchievement: achievement, gamesPlayed: counts.gamesPlayed)
    }

    @Test func poolIsNeverEmpty() {
        #expect(!SuperfanSpotlight.pool(input(.zero)).isEmpty)
        var full = SuperfanCounts()
        full.predictCorrect = 5; full.predictTotal = 10
        #expect(!SuperfanSpotlight.pool(input(full)).isEmpty)
    }

    @Test func zeroStateIsPlayfulNotBlank() {
        let items = SuperfanSpotlight.pool(input(.zero))
        #expect(items.contains { $0.tone == .playful })
        #expect(items.contains { $0.headline.contains("Fan tier") })
    }

    @Test func nextTierNudgeNamesTheGapAndTier() {
        // KHG 100% (1.0^gamma == 1 → 20) + full momentum = 25 exactly → Rising, next tier All-Star (50).
        var c = SuperfanCounts()
        c.khgCorrect = 10; c.khgTotal = 10; c.khgMomentum = 5
        #expect(SuperfanScoring.total(counts: c) == 25)
        let items = SuperfanSpotlight.pool(input(c))
        #expect(items.contains { $0.headline == "25 to All-Star" && $0.tone == .nudge })
    }

    @Test func anUntappedChannelIsSurfacedAsOpportunity() {
        var c = SuperfanCounts()
        c.khgCorrect = 8; c.khgTotal = 10        // only KHG played; the other three are untapped
        let items = SuperfanSpotlight.pool(input(c))
        #expect(items.contains { $0.headline.contains("untapped") })
    }

    @Test func playersLearnedItemOnlyWhenTheCollectionIsNonEmpty() {
        var c = SuperfanCounts(); c.khgCorrect = 4; c.khgTotal = 10
        #expect(!SuperfanSpotlight.pool(input(c, playersLearned: 0)).contains { $0.headline.contains("learned") })
        #expect(SuperfanSpotlight.pool(input(c, playersLearned: 3)).contains { $0.headline == "3 players learned" })
    }

    @Test func personalBestAndAchievementSurfaceWhenReal() {
        var c = SuperfanCounts(); c.predictCorrect = 20; c.predictTotal = 55
        let withBest = SuperfanSpotlight.pool(input(c, best: 8))
        #expect(withBest.contains { $0.headline.contains("Best Predict week: 8 of 11") })
        // A thin best (< 6) isn't worth boasting about — no item.
        #expect(!SuperfanSpotlight.pool(input(c, best: 3)).contains { $0.headline.contains("Best Predict") })
        #expect(SuperfanSpotlight.pool(input(c, achievement: "Upset Royalty")).contains { $0.headline == "Upset Royalty" })
    }

    @Test func pickRotatesAndSurvivesAnyRotationInt() {
        var c = SuperfanCounts(); c.khgCorrect = 5; c.khgTotal = 10; c.khgMomentum = 2
        let p = SuperfanSpotlight.pool(input(c))
        #expect(p.count >= 2)   // enough to actually rotate
        #expect(SuperfanSpotlight.pick(input(c), rotation: 0) == p[0])
        #expect(SuperfanSpotlight.pick(input(c), rotation: 1) == p[1 % p.count])
        // A negative rotation must not crash (safe modulo).
        #expect(SuperfanSpotlight.pick(input(c), rotation: -1) != nil)
    }
}
