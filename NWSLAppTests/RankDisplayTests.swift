//
//  RankDisplayTests.swift
//  NWSLAppTests
//
//  Pins the two failures that made the Bracket rank line misleading (roadmap 🐞, fixed 2026-07-31):
//  a percentile computed over a field too small to support one, and a bad percentile drawn in the
//  praise colour. The WORDING ("top 3%") is deliberately kept — it is a well-understood idiom
//  (Spotify Wrapped, class rank) and was never the problem.
//

import Testing
@testable import NWSLApp

struct RankDisplayTests {

    // MARK: - Small fields can't express winning

    @Test func firstPlaceInATinyFieldShowsPlacingNotAPercentile() {
        // The bug: rank 1 of 12 rendered "top 8%", and rank 1 of 2 rendered "top 50%" — the number
        // described the field size, not the fan, and made WINNING look ordinary.
        #expect(RankDisplay(rank: 1, total: 12).summary() == "1st of 12 fans")
        #expect(RankDisplay(rank: 1, total: 2).summary() == "1st of 2 fans")
        #expect(RankDisplay(rank: 1, total: 1).summary() == "1st of 1 fan")   // singular unit
    }

    @Test func placingUsesCorrectOrdinals() {
        #expect(RankDisplay(rank: 2, total: 20).ordinal == "2nd")
        #expect(RankDisplay(rank: 3, total: 20).ordinal == "3rd")
        #expect(RankDisplay(rank: 4, total: 20).ordinal == "4th")
        // The teens are the exception — 11th/12th/13th, not 11st/12nd/13rd.
        #expect(RankDisplay(rank: 11, total: 40).ordinal == "11th")
        #expect(RankDisplay(rank: 12, total: 40).ordinal == "12th")
        #expect(RankDisplay(rank: 13, total: 40).ordinal == "13th")
        #expect(RankDisplay(rank: 21, total: 40).ordinal == "21st")
        #expect(RankDisplay(rank: 22, total: 40).ordinal == "22nd")
        #expect(RankDisplay(rank: 111, total: 200).ordinal == "111th")
    }

    @Test func percentileAppearsOnceTheFieldCanSupportOne() {
        #expect(RankDisplay(rank: 1, total: 49).usesPercentile == false)
        #expect(RankDisplay(rank: 1, total: 50).usesPercentile == true)
        #expect(RankDisplay(rank: 1, total: 200).summary() == "top 1% of 200 fans")
        #expect(RankDisplay(rank: 60, total: 200).summary() == "top 30% of 200 fans")
    }

    // MARK: - The praise-styling inversion

    @Test func aNearLastFinishIsNotStyledAsPraise() {
        // The original report: rank 30 of 32 rendered "top 94%" in the ACCENT colour, reading as an
        // achievement. (At 32 players it now shows placing anyway; the styling rule is what matters.)
        let nearLast = RankDisplay(rank: 940, total: 1000)
        #expect(nearLast.topPercent == 94)
        #expect(nearLast.isPraiseworthy == false)
        #expect(nearLast.resultsSentence == "You finished in the top 94%")
    }

    @Test func aGenuinelyGoodFinishKeepsThePraiseTreatment() {
        let elite = RankDisplay(rank: 3, total: 1000)
        #expect(elite.isPraiseworthy == true)
        #expect(elite.resultsSentence == "You're in the top 1%")
    }

    @Test func praiseStopsAtTheThresholdAndNeverAppliesToPlacings() {
        #expect(RankDisplay(rank: 25, total: 100).isPraiseworthy == true)    // exactly 25% — still good news
        #expect(RankDisplay(rank: 26, total: 100).isPraiseworthy == false)   // 26% — stated, not celebrated
        // A small field shows a placing, which carries no percentile to celebrate.
        #expect(RankDisplay(rank: 1, total: 10).isPraiseworthy == false)
        #expect(RankDisplay(rank: 1, total: 10).resultsSentence == "You finished 1st of 10")
    }

    // MARK: - Arithmetic edges

    @Test func percentileRoundsUpSoTheBoundaryNeverOverFlatters() {
        // rank 3 of 100 is "top 3%", never "top 2%" — rounding down would claim a place you don't hold.
        #expect(RankDisplay(rank: 3, total: 100).topPercent == 3)
        #expect(RankDisplay(rank: 15, total: 1000).topPercent == 2)  // 1.5% → 2%
        #expect(RankDisplay(rank: 1, total: 1000).topPercent == 1)   // never 0%
    }

    @Test func lastPlaceCapsAtOneHundredAndZeroTotalDoesNotCrash() {
        #expect(RankDisplay(rank: 1000, total: 1000).topPercent == 100)
        #expect(RankDisplay(rank: 0, total: 0).topPercent == 100)     // no divide-by-zero
        #expect(RankDisplay(rank: 5, total: 0).usesPercentile == false)
    }

    @Test func compactSuffixOmitsTheRedundantTotal() {
        // Used where the rank is already stated ("#8 of 200 fans · top 4%").
        #expect(RankDisplay(rank: 8, total: 200).suffix() == "top 4%")
        #expect(RankDisplay(rank: 8, total: 20).suffix() == "of 20 fans")
    }
}
