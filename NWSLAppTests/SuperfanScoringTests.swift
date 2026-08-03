//
//  SuperfanScoringTests.swift
//  NWSLAppTests
//
//  The Superfan 0–100 accuracy economy (SuperfanScoring / SuperfanCounts) — every game contributes
//  accuracy × 25, Trivia adds a capped streak bonus, and the counts merge reinstall-safe. Pure, no I/O.
//

import Foundation
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

    // MARK: - the Home-card/detail equality contract (SuperfanCountsCache, 2026-07-25)

    @Test func cacheRoundTripsAndMergesToTheDetailScore() {
        // The 25-vs-46 mismatch: after a reinstall the Home card computed from local-only counts
        // while the detail adopted the server merge. The card now computes
        // local.merged(with: cachedServerMerge) — assert that equals the detail's adopted total.
        let suite = "test.superfan.countscache"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        // Post-reinstall device: only a corrupt-ish trivia round locally; history on the server.
        let local = SuperfanCounts(triviaCorrect: 0, triviaTotal: 10)
        let server = SuperfanCounts(bracketCorrect: 3, bracketTotal: 25,
                                    khgCorrect: 14, khgTotal: 20,
                                    triviaCorrect: 25, triviaTotal: 25)
        let adopted = local.merged(with: server)          // what the detail screen shows

        SuperfanCountsCache.save(adopted, season: 2026, defaults: defaults)
        let cardCounts = local.merged(with: SuperfanCountsCache.load(season: 2026, defaults: defaults))
        #expect(SuperfanScoring.total(counts: cardCounts) == SuperfanScoring.total(counts: adopted))

        // Never-synced device: loading yields .zero, and merging with zero is the identity —
        // the card safely shows the local-only score until the first sync.
        defaults.removePersistentDomain(forName: suite)
        #expect(SuperfanCountsCache.load(season: 2026, defaults: defaults) == .zero)
        #expect(local.merged(with: .zero) == local)
    }

    // MARK: - The cache must never go DOWN (2026-08-03)

    @Test func cacheWriteNeverLowersAStoredValue() {
        // ⚠️ `SuperfanService.submit` returns the CALLER'S OWN counts when the network fails. Saving
        // that verbatim is how a cached 62 became a 25 on the next offline launch — the Home card
        // silently losing progress the user really earned. Both writers now merge with what's already
        // cached, so a failed read can only ever leave the number where it was.
        let suite = "test.superfan.cache.monotonic"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let adopted = SuperfanCounts(predictCorrect: 40, predictTotal: 50,
                                     khgCorrect: 18, khgTotal: 20)
        SuperfanCountsCache.save(adopted, season: 2026, defaults: defaults)
        let before = SuperfanScoring.total(counts: SuperfanCountsCache.load(season: 2026, defaults: defaults))

        // The offline launch: submit hands back the thin local counts.
        let thinLocal = SuperfanCounts(predictCorrect: 4, predictTotal: 5)
        let guarded = thinLocal.merged(with: SuperfanCountsCache.load(season: 2026, defaults: defaults))
        SuperfanCountsCache.save(guarded, season: 2026, defaults: defaults)

        let after = SuperfanScoring.total(counts: SuperfanCountsCache.load(season: 2026, defaults: defaults))
        #expect(after >= before, "a failed sync must never lower the cached Superfan score")
        #expect(SuperfanCountsCache.load(season: 2026, defaults: defaults) == adopted)
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func zeroLocalDeviceStillAdoptsTheServerScore() {
        // The replacement phone, which is the whole point of the durable tier: nothing local, a full
        // season on the server. The adopt must survive the anti-churn guard that stops it WRITING —
        // read and write are separate calls precisely so this case works.
        let local = SuperfanCounts.zero
        let server = SuperfanCounts(predictCorrect: 44, predictTotal: 55,
                                    bracketCorrect: 9, bracketTotal: 16,
                                    khgCorrect: 17, khgTotal: 20,
                                    triviaCorrect: 22, triviaTotal: 30)
        let adopted = local.merged(with: server)
        #expect(adopted == server)
        #expect(SuperfanScoring.total(counts: adopted) > 0,
                "a returning user must not be shown 0 just because this device is new")
    }
}

/// Game Center submission gating (`isWorthSubmitting`).
///
/// Extracted as a pure rule because `GameCenterManager` is a `@MainActor` GameKit singleton with no
/// seam — same reason `shouldCascadeBundle` was extracted from the notification coordinator.
@Suite("Game Center submission gating")
struct GameCenterSubmitGateTests {

    @Test func zeroIsNeverSubmitted() {
        // ⚠️ `syncAll` fires on every foreground and whenever GC authenticates — including on a fresh
        // or replaced device before the server restore lands, when every local total is still 0.
        // On a board configured "Most Recent Score" that 0 would replace a real earned total.
        #expect(!GameCenterManager.isWorthSubmitting(0))
    }

    @Test func realScoresAreSubmitted() {
        #expect(GameCenterManager.isWorthSubmitting(1))
        #expect(GameCenterManager.isWorthSubmitting(88))
    }

    @Test func negativeIsNeverSubmitted() {
        // Not reachable today (every board is a non-negative total), but a negative is even less
        // meaningful than a zero and the rule should not depend on that staying true.
        #expect(!GameCenterManager.isWorthSubmitting(-1))
    }
}
