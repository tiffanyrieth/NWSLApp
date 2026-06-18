//
//  BundledAssetTests.swift
//  NWSLAppTests
//
//  CI guard for the first-launch asset bundle: every crest + featured flag MUST resolve from
//  the app bundle, and the BundledAssetManifest must stay in lockstep with what's actually
//  bundled. A bundled asset must never silently fall through to the network in a shipped build
//  (principle: no silent failures) — so a missing/unloadable asset fails the build here.
//
//  Runs hosted (TEST_HOST = NWSLApp.app), so `UIImage(named:)` resolves from the compiled
//  asset catalog. Keep the abbreviation list in sync with the bundled Crests/ group.
//

import UIKit
import Testing
@testable import NWSLApp

struct BundledAssetTests {
    // All 16 NWSL crests are bundled (11 vector + 5 raster).
    private let crests = ["LA","BAY","BOS","CHI","DEN","GFC","HOU","KC","NC","SEA","ORL","POR","LOU","SD","UTA","WAS"]

    @Test func everyCrestResolvesFromBundle() {
        for abbr in crests {
            #expect(UIImage(named: "Crests/\(abbr)") != nil, "Crests/\(abbr) is missing or won't load")
        }
    }

    @Test func everyFeaturedFlagResolvesFromBundle() {
        for code in NationalTeam.featured.map(\.code) {
            #expect(UIImage(named: "Flags/\(code)") != nil, "Flags/\(code) is missing or won't load")
        }
    }

    // The manifest the rebrand-refresh diffs against must describe exactly what's bundled —
    // a drift would silently mis-detect (or miss) a rebrand.
    @Test func manifestCoversExactlyTheBundledCrests() {
        #expect(Set(BundledAssetManifest.crests.keys) == Set(crests))
        for abbr in crests {
            #expect(UIImage(named: "Crests/\(abbr)") != nil)
        }
    }

    @Test func manifestCoversExactlyTheFeaturedFlags() {
        #expect(Set(BundledAssetManifest.flags.keys) == Set(NationalTeam.featured.map(\.code)))
    }

    // Browse-all (non-featured) flags are intentionally NOT bundled — they're download-and-cache,
    // so the country list isn't chained to app releases (rule: bundle = featured).
    @Test func nonFeaturedFlagsAreNotBundled() {
        let featured = Set(NationalTeam.featured.map(\.code))
        for team in NationalTeam.all where !featured.contains(team.code) {
            #expect(UIImage(named: "Flags/\(team.code)") == nil, "Flags/\(team.code) should not be bundled")
        }
    }

    // The vector/raster split the no-downgrade rule relies on must match reality.
    @Test func rasterCrestSetIsExactlyTheNoVectorTeams() {
        #expect(BundledAssetManifest.rasterCrests == ["CHI","KC","BOS","DEN","GFC"])
        #expect(BundledAssetManifest.isVectorCrest("WAS"))
        #expect(!BundledAssetManifest.isVectorCrest("CHI"))
    }
}
