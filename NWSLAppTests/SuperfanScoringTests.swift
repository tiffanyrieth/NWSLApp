//
//  SuperfanScoringTests.swift
//  NWSLAppTests
//
//  The Superfan 0–100 economy (SuperfanScoring / SuperfanCounts), REBUILT 2026-08-04 — each channel is
//  accuracy × 20 + forgiving engagement momentum (0–5); a tier-floor lock holds the displayed score at a
//  tier you've earned; the counts merge reinstall-safe. Pure, no I/O.
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

    @Test func contributionAppliesTheTopWeightedCurvePlusMomentum() {
        var c = SuperfanCounts()
        c.bracketCorrect = 16; c.bracketTotal = 25          // 64% accuracy (gentle curve — a luck game)
        let expected = pow(0.64, SuperfanScoring.accuracyGamma[.bracket]!) * 20
        #expect(abs(SuperfanScoring.contribution(for: .bracket, counts: c) - expected) < 0.0001)
        c.bracketMomentum = 3
        #expect(abs(SuperfanScoring.contribution(for: .bracket, counts: c) - (expected + 3)) < 0.0001)
        #expect(expected < 0.64 * 20)   // the curve is stingier than flat ×20 in the middle (the point)
    }

    @Test func topWeightedCurveKeepsPerfectFullButMakesTheMiddleCostMore() {
        // 1.0^gamma == 1 → perfect accuracy still earns the full 20 (the curve only taxes the middle).
        var perfect = SuperfanCounts(); perfect.khgCorrect = 10; perfect.khgTotal = 10
        #expect(abs(SuperfanScoring.accuracyPoints(for: .khg, counts: perfect) - 20) < 0.0001)
        // Skill game (steeper gamma) is stingier at the same 80% than a luck game (gentler gamma).
        var k = SuperfanCounts(); k.khgCorrect = 8; k.khgTotal = 10
        var p = SuperfanCounts(); p.predictCorrect = 8; p.predictTotal = 10
        #expect(SuperfanScoring.accuracyPoints(for: .khg, counts: k)
              < SuperfanScoring.accuracyPoints(for: .predict, counts: p))
    }

    // MARK: - Engagement momentum (0–5, forgiving)

    @Test func engagementAddsUpToFivePointsAndCapsThere() {
        var c = SuperfanCounts()
        c.khgCorrect = 5; c.khgTotal = 10; c.khgMomentum = 5
        #expect(SuperfanScoring.engagementPoints(for: .khg, counts: c) == 5)
        let acc = SuperfanScoring.accuracyPoints(for: .khg, counts: c)
        #expect(abs(SuperfanScoring.contribution(for: .khg, counts: c) - (acc + 5)) < 0.0001)
        c.khgMomentum = 99                                       // clamps to the max
        #expect(SuperfanScoring.engagementPoints(for: .khg, counts: c) == 5)
    }

    @Test func contributionNeverExceeds25AtPerfectAccuracyPlusFullMomentum() {
        var c = SuperfanCounts()
        c.triviaCorrect = 10; c.triviaTotal = 10; c.triviaMomentum = 5   // 20 + 5
        #expect(SuperfanScoring.contribution(for: .trivia, counts: c) == 25.0)
    }

    @Test func momentumIsPerChannelAndDoesNotLeak() {
        var c = SuperfanCounts()
        c.predictCorrect = 5; c.predictTotal = 10; c.triviaMomentum = 5   // trivia momentum must not touch predict
        let expected = SuperfanScoring.accuracyPoints(for: .predict, counts: c)  // accuracy only, no leaked engagement
        #expect(abs(SuperfanScoring.contribution(for: .predict, counts: c) - expected) < 0.0001)
    }

    // MARK: - Total

    @Test func totalSumsFourChannelsAndClampsTo100() {
        var c = SuperfanCounts()
        c.predictCorrect = 11; c.predictTotal = 11; c.predictMomentum = 5   // 25
        c.bracketCorrect = 10; c.bracketTotal = 10; c.bracketMomentum = 5   // 25
        c.khgCorrect = 10; c.khgTotal = 10; c.khgMomentum = 5               // 25
        c.triviaCorrect = 10; c.triviaTotal = 10; c.triviaMomentum = 5      // 25
        #expect(SuperfanScoring.total(counts: c) == 100)
        #expect(SuperfanTier.forScore(SuperfanScoring.total(counts: c)) == .mvp)
    }

    @Test func pureAccuracyAloneCapsAtEightyWithoutEngagement() {
        // 100% in all four but zero momentum = 80/100 — you must SHOW UP (engagement) for the top 20.
        var c = SuperfanCounts()
        c.predictCorrect = 11; c.predictTotal = 11
        c.bracketCorrect = 10; c.bracketTotal = 10
        c.khgCorrect = 10; c.khgTotal = 10
        c.triviaCorrect = 10; c.triviaTotal = 10
        #expect(SuperfanScoring.total(counts: c) == 80)
    }

    // MARK: - Tier-floor lock

    @Test func displayScoreHoldsAtAnEarnedTierFloor() {
        var c = SuperfanCounts()
        c.predictCorrect = 8; c.predictTotal = 20    // 40% → 8 pts total, well under 50
        #expect(SuperfanScoring.total(counts: c) < 50)
        // A season peak of 55 earned the All-Star floor (50) → the displayed score can't drop below it.
        #expect(SuperfanScoring.displayScore(counts: c, seasonPeak: 55) == 50)
        #expect(SuperfanScoring.tierFloor(peakScore: 30) == 25)   // only reached Rising
        #expect(SuperfanScoring.tierFloor(peakScore: 10) == 0)    // never above Fan
        // When the raw total is above the floor, the floor is a no-op.
        var hi = SuperfanCounts(); hi.predictCorrect = 20; hi.predictTotal = 20; hi.predictMomentum = 5  // 25
        #expect(SuperfanScoring.displayScore(counts: hi, seasonPeak: 25) == SuperfanScoring.total(counts: hi))
    }

    // MARK: - Breakdown consistency (accuracy + engagement split out)

    @Test func breakdownSplitsAccuracyAndEngagement() {
        var c = SuperfanCounts()
        c.triviaCorrect = 5; c.triviaTotal = 10; c.triviaMomentum = 3   // 50% + 3
        let ch = SuperfanScoring.breakdown(counts: c).channel(for: .trivia)
        #expect(abs(ch.accuracyRatio - 0.5) < 0.0001)
        #expect(abs(ch.accuracyPoints - pow(0.5, SuperfanScoring.accuracyGamma[.trivia]!) * 20) < 0.0001)
        #expect(ch.engagementPoints == 3)
        #expect(abs(ch.contribution - (ch.accuracyPoints + 3)) < 0.0001)
    }

    // MARK: - Reinstall-safe merge

    @Test func mergeTakesTheFullerPairWholeAndHigherMomentum() {
        // DISCRIMINATING data: local has the HIGHER correct but the LOWER total. The old per-scalar
        // max took (max correct 10, max total 22) = a 45% accuracy from a numerator and denominator
        // that never coexisted on one device. Atomic-pair takes the fuller side (server, 22 attempts)
        // WHOLE — its own (8, 22).
        let local = SuperfanCounts(predictCorrect: 10, predictTotal: 11, predictMomentum: 2)
        let server = SuperfanCounts(predictCorrect: 8, predictTotal: 22, predictMomentum: 4)
        let merged = local.merged(with: server)
        #expect(merged.predictCorrect == 8)     // server's numerator, NOT local's 10
        #expect(merged.predictTotal == 22)      // paired with server's own denominator
        #expect(merged.predictMomentum == 4)    // momentum is standalone → still the higher side
    }

    @Test func mergeNeverSynthesizesAnAccuracyNeitherDeviceHad() {
        // local = a perfect small sample (5/5 = 100%), server = a fuller lower one (4/6 = 67%).
        // Old max → (5, 6) = 83%, an accuracy neither device produced. Atomic-pair → server's real
        // (4, 6). The correct count never exceeds its paired total.
        let local = SuperfanCounts(khgCorrect: 5, khgTotal: 5)
        let server = SuperfanCounts(khgCorrect: 4, khgTotal: 6)
        let merged = local.merged(with: server)
        #expect(merged.khgCorrect == 4)
        #expect(merged.khgTotal == 6)
        #expect(merged.khgCorrect <= merged.khgTotal)
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
