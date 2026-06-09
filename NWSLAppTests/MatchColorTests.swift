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
}
