//
//  SuperfanMomentumTests.swift
//  NWSLAppTests
//
//  The forgiving engagement momentum (SuperfanMomentum) — +1 played, −1 per missed cycle, floored/capped,
//  never a reset, decays if you stop. Pure math over explicit week ordinals.
//

import Foundation
import Testing
@testable import NWSLApp

struct SuperfanMomentumTests {
    typealias M = SuperfanMomentum

    @Test func neverPlayedIsZero() {
        #expect(M.effective(state: nil, game: .khg, currentWeek: 100) == 0)
    }

    @Test func firstPlayIsOne() {
        #expect(M.afterPlay(state: nil, game: .khg, currentWeek: 100) == M.State(momentum: 1, lastWeek: 100))
    }

    @Test func consecutivePlaysBuildToTheCap() {
        var s: M.State? = nil
        for w in stride(from: 100, through: 112, by: 2) { s = M.afterPlay(state: s, game: .khg, currentWeek: w) }
        #expect(s?.momentum == 5)   // caps at engagementMax
    }

    @Test func missedCyclesDecayOnePerCycleFlooredAtZero() {
        let s = M.State(momentum: 4, lastWeek: 100)   // KHG, cadence 2 weeks
        #expect(M.effective(state: s, game: .khg, currentWeek: 100) == 4)   // same week
        #expect(M.effective(state: s, game: .khg, currentWeek: 102) == 4)   // current cycle — not "missed" yet
        #expect(M.effective(state: s, game: .khg, currentWeek: 104) == 3)   // 1 cycle missed
        #expect(M.effective(state: s, game: .khg, currentWeek: 108) == 1)   // 3 missed
        #expect(M.effective(state: s, game: .khg, currentWeek: 120) == 0)   // floored, never negative
    }

    @Test func missingOneCycleThenReturningIsForgivingNotAReset() {
        let s0 = M.State(momentum: 4, lastWeek: 100)
        let s1 = M.afterPlay(state: s0, game: .khg, currentWeek: 104)   // skipped the week-102 cycle
        #expect(s1.momentum == 4)   // 4 → decayed to 3 for the one miss → +1 = 4, not a wipeout
    }

    @Test func cadenceDiffersByGame() {
        let s = M.State(momentum: 5, lastWeek: 100)
        #expect(M.effective(state: s, game: .predict, currentWeek: 102) == 4)  // weekly: 2 weeks = 1 missed
        #expect(M.effective(state: s, game: .khg, currentWeek: 102) == 5)      // biweekly: 2 weeks = same cycle
    }
}
