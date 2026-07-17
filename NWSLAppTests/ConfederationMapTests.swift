//
//  ConfederationMapTests.swift
//  NWSLAppTests
//
//  Country → confederation → feed scoping (the 2026-07-16 polling-efficiency fix).
//  Locks: completeness over every followable curated country (the map can't silently miss),
//  the ZAM/USA scoping the owner specified (a country only polls feeds it can appear in,
//  plus the globals that admit anyone), the multi-follow union, and the fail-OPEN unmapped
//  fallback (coverage may degrade to the old all-feeds cost, never to a missed fixture).
//

import Foundation
import Testing
@testable import NWSLApp

struct ConfederationMapTests {

    private func slugs(_ feeds: [NationalTeamFeed]) -> Set<String> { Set(feeds.map(\.slug)) }

    private let globalSlugs: Set<String> = [
        "fifa.friendly.w", "fifa.shebelieves", "fifa.wwc", "fifa.w.olympics",
        "fifa.wwcq.ply", "global.pinatar_cup",
    ]

    // MARK: Completeness

    /// Every country the app curates as followable MUST map — a miss here would mean a real
    /// user silently riding the fail-open path forever.
    @Test func everyCuratedCountryMaps() {
        for team in NationalTeam.all {
            #expect(ConfederationMap.confederation(for: team.code) != nil, "unmapped curated code: \(team.code)")
        }
    }

    /// Every feed carries a deliberate scope tag: the confed feeds match their slug's region,
    /// and exactly the six cross-confederation feeds are global.
    @Test func feedScopeTagsAreComplete() {
        let globals = NationalTeamFeed.all.filter { $0.scope == .global }
        #expect(slugs(globals) == globalSlugs)
        #expect(NationalTeamFeed.all.first { $0.slug == "caf.w.nations" }?.scope == .confed(.caf))
        #expect(NationalTeamFeed.all.first { $0.slug == "uefa.weuro" }?.scope == .confed(.uefa))
        #expect(NationalTeamFeed.all.first { $0.slug == "concacaf.w.gold" }?.scope == .confed(.concacaf))
        #expect(NationalTeamFeed.all.first { $0.slug == "afc.w.asian.cup" }?.scope == .confed(.afc))
        #expect(NationalTeamFeed.all.first { $0.slug == "conmebol.america.femenina" }?.scope == .confed(.conmebol))
    }

    // MARK: The owner's worked example — ZAM

    /// Zambia (CAF): WAFCON + the globals (their EGY/NGA/MWI Africa Cup games + the CAN/BRA/NOR
    /// friendlies from the owner's phone check) — and NEVER another confederation's feeds.
    @Test func zambiaGetsCafPlusGlobalsOnly() {
        let (feeds, unmapped) = NationalTeamFeed.scopedFeeds(forFollowedCodes: ["ZAM"])
        #expect(unmapped.isEmpty)
        let s = slugs(feeds)
        #expect(s == globalSlugs.union(["caf.w.nations"]))
        #expect(!s.contains("uefa.weuro"))
        #expect(!s.contains("concacaf.w.gold"))
        #expect(feeds.count == 7)   // was 15 — the whole point
    }

    @Test func usaGetsConcacafSet() {
        let (feeds, unmapped) = NationalTeamFeed.scopedFeeds(forFollowedCodes: ["USA"])
        #expect(unmapped.isEmpty)
        let s = slugs(feeds)
        #expect(s.contains("concacaf.w.gold"))
        #expect(s.contains("concacaf.womens.championship"))
        #expect(s.contains("fifa.w.concacaf.olympicsq"))
        #expect(!s.contains("caf.w.nations"))
        #expect(!s.contains("uefa.w.nations"))
    }

    /// Case-insensitive on the code (follows persist lowercase ids in places).
    @Test func codeLookupIsCaseInsensitive() {
        #expect(ConfederationMap.confederation(for: "zam") == .caf)
    }

    // MARK: Union + edges

    @Test func multiConfederationFollowUnions() {
        let (feeds, unmapped) = NationalTeamFeed.scopedFeeds(forFollowedCodes: ["ZAM", "NOR"])
        #expect(unmapped.isEmpty)
        let s = slugs(feeds)
        #expect(s.contains("caf.w.nations"))
        #expect(s.contains("uefa.weuro"))
        #expect(s.contains("uefa.w.nations"))
        #expect(!s.contains("afc.w.asian.cup"))
    }

    /// OFC (e.g. New Zealand) has no ESPN confederation feed today → globals only, no error.
    @Test func oceaniaGetsGlobalsOnly() {
        let (feeds, unmapped) = NationalTeamFeed.scopedFeeds(forFollowedCodes: ["NZL"])
        #expect(unmapped.isEmpty)
        #expect(slugs(feeds) == globalSlugs)
    }

    /// Unknown code → fail OPEN: all feeds + the code reported (the caller emits the diag).
    @Test func unmappedCodeFailsOpen() {
        let (feeds, unmapped) = NationalTeamFeed.scopedFeeds(forFollowedCodes: ["XYZ", "ZAM"])
        #expect(unmapped == ["XYZ"])
        #expect(feeds.count == NationalTeamFeed.all.count)
    }

    @Test func emptyFollowsFetchNothing() {
        let (feeds, unmapped) = NationalTeamFeed.scopedFeeds(forFollowedCodes: [])
        #expect(feeds.isEmpty)
        #expect(unmapped.isEmpty)
    }
}
