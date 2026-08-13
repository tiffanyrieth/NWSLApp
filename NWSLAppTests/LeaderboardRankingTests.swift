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

    // MARK: - effectiveStanding (the reinstall fix, 2026-08-10). The You-row's source of truth
    // when local UserDefaults and the user's own server row disagree: the fuller record (more
    // matches) wins; ties go to local (fresher — includes a match scored since the last push).

    private func standing(_ points: Int, _ matches: Int) -> R.SeasonStanding {
        R.SeasonStanding(points: points, matches: matches,
                         avg: matches > 0 ? Double(points) / Double(matches) : 0)
    }

    @Test func effectiveStandingLocalOnly() {
        // Signed-in play before any push lands — local is all there is.
        let local = standing(88, 2)
        #expect(R.effectiveStanding(local: local, server: nil) == local)
    }

    @Test func effectiveStandingServerOnlyIsTheReinstallCase() {
        // The wiped device: local empty, server holds the season. The user MUST rank from this —
        // the old code gated the rank on local state and erased her from her own board.
        let server = standing(300, 15)
        #expect(R.effectiveStanding(local: nil, server: server) == server)
    }

    @Test func effectiveStandingFullerSideWins() {
        // A stale device (played 2, server has 15) ranks from the server…
        let stale = standing(40, 2), full = standing(300, 15)
        #expect(R.effectiveStanding(local: stale, server: full) == full)
        // …and a fresh unpushed score (local 16 > server 15) ranks from local.
        let fresh = standing(320, 16)
        #expect(R.effectiveStanding(local: fresh, server: full) == fresh)
    }

    @Test func effectiveStandingTieGoesToLocal() {
        // Same match count, different points (a regrade landed locally, push pending):
        // local is fresher and wins the tie.
        let local = standing(310, 15), server = standing(300, 15)
        #expect(R.effectiveStanding(local: local, server: server) == local)
    }

    @Test func effectiveStandingBothNilIsUnranked() {
        #expect(R.effectiveStanding(local: nil, server: nil) == nil)
    }

    // MARK: - fullerPair (the #10 atomic-pair rule shared by the persisted merges)

    @Test func fullerPairTakesTheGreaterDenominatorWhole() {
        // The #10 case verbatim: 100pts/5matches (local) vs 80/6 (server). The old per-scalar max
        // produced (100, 6) → avg 16.7, a number NEITHER device scored. fullerPair takes the fuller
        // side (6 matches) whole → (80, 6), a real 13.3 avg.
        let merged = R.fullerPair(local: (num: 100, den: 5), server: (num: 80, den: 6))
        #expect(merged.num == 80)
        #expect(merged.den == 6)
    }

    @Test func fullerPairNeverMixesNumeratorAndDenominatorAcrossSides() {
        // Whichever side wins, the returned pair is exactly one input pair — never a Frankenstein.
        let a = R.fullerPair(local: (num: 10, den: 11), server: (num: 8, den: 22))
        #expect(a == (num: 8, den: 22))
        let b = R.fullerPair(local: (num: 8, den: 22), server: (num: 10, den: 11))
        #expect(b == (num: 8, den: 22))
    }

    @Test func fullerPairTieGoesToLocal() {
        // Equal denominators (same attempts) → local wins, matching effectiveStanding's tiebreak.
        let merged = R.fullerPair(local: (num: 9, den: 10), server: (num: 7, den: 10))
        #expect(merged == (num: 9, den: 10))
    }

    @Test func fullerPairFreshInstallAdoptsTheServerWhole() {
        // Local zero (reinstall) always loses to a populated server — reinstall-safety preserved.
        let merged = R.fullerPair(local: (num: 0, den: 0), server: (num: 30, den: 44))
        #expect(merged == (num: 30, den: 44))
    }
}
