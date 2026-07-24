//
//  SuperfanScoringTests.swift
//  NWSLAppTests
//
//  The Superfan 0–100 accuracy economy (SuperfanScoring / SuperfanCounts) — every game contributes
//  accuracy × 25, Trivia adds a capped streak bonus, and the counts merge reinstall-safe. Pure, no I/O.
//

import Testing
@testable import NWSLApp

struct SuperfanScoringTests {

    // MARK: - Accuracy + contribution

    @Test func accuracyIsCorrectOverAttempted() {
        var c = SuperfanCounts()
        c.predictCorrect = 33; c.predictTotal = 44          // 3 matches × 11 = 44 slots, 33 right
        #expect(abs(SuperfanScoring.accuracy(for: .predict, counts: c) - 0.75) < 0.0001)
    }

    @Test func zeroAttemptsIsZeroNotDivideByZero() {
        let c = SuperfanCounts()   // nothing played
        #expect(SuperfanScoring.accuracy(for: .khg, counts: c) == 0)
        #expect(SuperfanScoring.contribution(for: .khg, counts: c) == 0)
        #expect(SuperfanScoring.total(counts: c) == 0)
    }

    @Test func contributionIsAccuracyTimes25() {
        var c = SuperfanCounts()
        c.bracketCorrect = 16; c.bracketTotal = 25          // 64% edition-wide accuracy
        #expect(abs(SuperfanScoring.contribution(for: .bracket, counts: c) - 16.0) < 0.0001)  // .64 × 25
    }

    // MARK: - Trivia streak bonus

    @Test func triviaStreakBonusAddsUpToTenPoints() {
        var c = SuperfanCounts()
        c.triviaCorrect = 5; c.triviaTotal = 10; c.triviaStreak = 8   // 50% base + 8pp = 58% effective
        // effective accuracy 0.58 → contribution 14.5
        #expect(abs(SuperfanScoring.contribution(for: .trivia, counts: c) - 14.5) < 0.0001)
    }

    @Test func triviaStreakBonusCapsAtTenAndContributionAt25() {
        var c = SuperfanCounts()
        c.triviaCorrect = 10; c.triviaTotal = 10; c.triviaStreak = 30  // 100% + big streak
        // effective capped at 1.0 → contribution capped at 25 (never > max)
        #expect(SuperfanScoring.contribution(for: .trivia, counts: c) == 25.0)
        // 95% base + 10 cap = 105% → clamps to 100% → 25
        var c2 = SuperfanCounts()
        c2.triviaCorrect = 19; c2.triviaTotal = 20; c2.triviaStreak = 50
        #expect(SuperfanScoring.contribution(for: .trivia, counts: c2) == 25.0)
    }

    @Test func nonTriviaGamesGetNoStreakBonus() {
        var c = SuperfanCounts()
        c.predictCorrect = 5; c.predictTotal = 10; c.triviaStreak = 10   // streak must not leak into predict
        #expect(SuperfanScoring.contribution(for: .predict, counts: c) == 12.5)   // .5 × 25, no bonus
    }

    // MARK: - Total

    @Test func totalSumsFourGamesAndClampsTo100() {
        var c = SuperfanCounts()
        c.predictCorrect = 11; c.predictTotal = 11   // 25
        c.bracketCorrect = 10; c.bracketTotal = 10   // 25
        c.khgCorrect = 10; c.khgTotal = 10           // 25
        c.triviaCorrect = 10; c.triviaTotal = 10     // 25 (no streak needed)
        #expect(SuperfanScoring.total(counts: c) == 100)
        #expect(SuperfanTier.forScore(SuperfanScoring.total(counts: c)) == .mvp)
    }

    @Test func totalMatchesTheDesignExample() {
        // The handoff's Superfan screen: Predict 72%, Bracket 64%, KHG 78%, Trivia 34% → 18+16+19.5+8.5 = 62.
        var c = SuperfanCounts()
        c.predictCorrect = 72; c.predictTotal = 100
        c.bracketCorrect = 64; c.bracketTotal = 100
        c.khgCorrect = 78; c.khgTotal = 100
        c.triviaCorrect = 34; c.triviaTotal = 100    // no streak, so 34% flat
        #expect(SuperfanScoring.total(counts: c) == 62)
        #expect(SuperfanTier.forScore(62) == .allStar)
    }

    // MARK: - Breakdown consistency (the % label == the bar)

    @Test func breakdownAccuracyEqualsContributionOver25() {
        var c = SuperfanCounts()
        c.triviaCorrect = 5; c.triviaTotal = 10; c.triviaStreak = 8   // effective 58%
        let b = SuperfanScoring.breakdown(counts: c)
        // The displayed accuracy folds in the streak bonus so the % and the "14.5 / 25" bar never disagree.
        #expect(abs(b.accuracy(for: .trivia) - 0.58) < 0.0001)
        #expect(abs(b.contribution(for: .trivia) - 14.5) < 0.0001)
    }

    // MARK: - Reinstall-safe merge

    @Test func mergeTakesGreatestOfEachCount() {
        let local = SuperfanCounts(predictCorrect: 5, predictTotal: 11, triviaStreak: 2)
        let server = SuperfanCounts(predictCorrect: 8, predictTotal: 22, triviaStreak: 6)
        let merged = local.merged(with: server)
        #expect(merged.predictCorrect == 8)
        #expect(merged.predictTotal == 22)
        #expect(merged.triviaStreak == 6)
    }

    @Test func mergeNeverLowersServerAfterReinstall() {
        // Fresh install (all zero) reconciling against a populated server keeps the server counts.
        let fresh = SuperfanCounts.zero
        let server = SuperfanCounts(predictCorrect: 30, predictTotal: 44,
                                    bracketCorrect: 16, bracketTotal: 25)
        let merged = fresh.merged(with: server)
        #expect(merged == server)
        #expect(SuperfanScoring.total(counts: merged) == SuperfanScoring.total(counts: server))
    }

    // MARK: - games played (no unlock gate)

    @Test func gamesPlayedCountsAnyGameWithAtLeastOneAttempt() {
        var c = SuperfanCounts()
        #expect(c.gamesPlayed == 0)
        c.predictTotal = 11        // played once — contributes immediately, no minimum
        c.triviaTotal = 10
        #expect(c.gamesPlayed == 2)
    }
}
