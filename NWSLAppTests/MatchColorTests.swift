//
//  MatchColorTests.swift
//  NWSLAppTests
//
//  Verifies Color.resolveMatchColors keeps the two teams in a match visibly
//  distinct + legible on dark — the case that actually broke (two black-primary
//  clubs, WAS vs POR, collapsing to identical gray).
//

import Foundation
import Testing
import SwiftUI
@testable import NWSLApp

struct MatchColorTests {

    private func brightness(_ c: (r: Double, g: Double, b: Double)) -> Double {
        0.299 * c.r + 0.587 * c.g + 0.114 * c.b
    }

    @Test func blackPrimariesResolveToDistinctColors() {
        // WAS (#000000, alt #ede939 yellow) vs POR (#000000, alt #99242B red).
        let r = Color._resolveMatchRGBForTesting(
            homePrimary: "000000", homeAlt: "ede939",
            awayPrimary: "000000", awayAlt: "99242B"
        )
        // Neither stays black-on-black, and they're well separated.
        #expect(brightness(r.home) > 0.2)
        #expect(r.separation >= 0.30)
    }

    @Test func brightPrimariesPassThroughAndStayDistinct() {
        // Houston (#ff6900 orange) vs Gotham (#a9f1fd light cyan) — both bright,
        // both used as-is, clearly different.
        let r = Color._resolveMatchRGBForTesting(
            homePrimary: "ff6900", homeAlt: "8ab7e9",
            awayPrimary: "a9f1fd", awayAlt: "000000"
        )
        #expect(r.home.r > 0.8 && r.home.g > 0.3)   // orange survived
        #expect(r.separation >= 0.30)
    }

    @Test func nearIdenticalColorsAreForcedApart() {
        // Two clubs whose only usable colors are nearly the same blue.
        let r = Color._resolveMatchRGBForTesting(
            homePrimary: "1133aa", homeAlt: nil,
            awayPrimary: "1133ad", awayAlt: nil
        )
        #expect(r.separation >= 0.30)
    }

    @Test func missingHexFallsBackToDistinctDefaults() {
        let r = Color._resolveMatchRGBForTesting(
            homePrimary: nil, homeAlt: nil,
            awayPrimary: nil, awayAlt: nil
        )
        #expect(r.separation >= 0.30)   // blue vs orange defaults
    }

    // MARK: - Brand-color overrides

    @Test func angelCityOverridesToSolRosa() {
        // ESPN id 21422 → Sol Rosa coral, not ESPN's #202121 black.
        #expect(TeamBrandColors.primary(for: "21422") == "E6447B")
        #expect(TeamBrandColors.alternate(for: "21422") == "202121")
    }

    @Test func unknownAndNilTeamsHaveNoOverride() {
        #expect(TeamBrandColors.primary(for: "15365") == nil)   // WAS — ESPN stands
        #expect(TeamBrandColors.primary(for: nil) == nil)
    }

    @Test func solRosaResolvesToCoralFill() {
        // Used directly (bright enough), reads as coral: red-dominant, low green.
        let r = Color._resolveMatchRGBForTesting(
            homePrimary: "E6447B", homeAlt: "202121",
            awayPrimary: "000000", awayAlt: "99242B"
        )
        #expect(r.home.r > 0.8)
        #expect(r.home.g < 0.4)
        #expect(r.separation >= 0.30)
    }
}
