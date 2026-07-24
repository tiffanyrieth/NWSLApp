//
//  ClubOrderRotationTests.swift
//  NWSLAppTests
//
//  Equal representation has TWO halves. The slot allowance (ContentRoundRobinTests) guarantees each
//  followed club the same NUMBER of cards. This file guards the other half: which club is seen
//  FIRST. Both content surfaces handed the round-robin a FIXED club order — Home sorted by
//  abbreviation, the Social feed used the directory's order — so following LA + ORL + WAS put Angel
//  City first, Pride second, Spirit third, on every launch and every pull-to-refresh, permanently.
//  A quiet club could hold its full slot count and still always be the one you had to scroll to find.
//
//  Both surfaces now rotate the starting club through `ContentRoundRobin.rotate` (the same helper
//  that shifts the per-club card windows), seeded randomly per launch and advanced on each refresh.
//

import Foundation
import Testing
@testable import NWSLApp

struct ClubOrderRotationTests {

    private let clubs = ["LA", "ORL", "WAS"]   // ACFC, Pride, Spirit — the owner's own follow set

    @Test func rotationAdvancesTheLeaderAndWraps() {
        #expect(ContentRoundRobin.rotate(clubs, by: 0) == ["LA", "ORL", "WAS"])
        #expect(ContentRoundRobin.rotate(clubs, by: 1) == ["ORL", "WAS", "LA"])
        #expect(ContentRoundRobin.rotate(clubs, by: 2) == ["WAS", "LA", "ORL"])
        #expect(ContentRoundRobin.rotate(clubs, by: 3) == ["LA", "ORL", "WAS"])   // wraps cleanly
    }

    @Test func rotationSurvivesDegenerateInput() {
        // Called while rendering, with whatever the user follows — it must never trap.
        #expect(ContentRoundRobin.rotate([String](), by: 7).isEmpty)
        #expect(ContentRoundRobin.rotate(["LA"], by: 7) == ["LA"])
        #expect(ContentRoundRobin.rotate(clubs, by: 1_000_000).count == 3)
        #expect(ContentRoundRobin.rotate(clubs, by: -1) == ["WAS", "LA", "ORL"])  // no negative-modulo crash
    }

    /// THE REGRESSION: over one full cycle every followed club leads exactly once. This is what makes
    /// it "no club is favoured" rather than merely "not always alphabetical" — a reshuffle could
    /// satisfy the latter while still handing the same club the lead twice running.
    @Test func everyClubLeadsExactlyOncePerCycle() {
        let leaders = (0..<clubs.count).map { ContentRoundRobin.rotate(clubs, by: $0).first! }
        #expect(Set(leaders) == Set(clubs))
        #expect(leaders.count == clubs.count)
    }

    /// Rotation reorders the clubs; it never adds, drops or duplicates one — so the per-club slot
    /// allowance downstream is provably untouched by this change.
    @Test func rotationIsAPermutationAtEveryOffset() {
        for offset in 0..<12 {
            let r = ContentRoundRobin.rotate(clubs, by: offset)
            #expect(Set(r) == Set(clubs))
            #expect(r.count == clubs.count)
        }
    }

    /// The rotation must not disturb the balance itself: whatever order the clubs arrive in, each
    /// club still contributes the same number of cards. Guards the Social feed's `arranged` (the
    /// pure entry point both tabs share the shape of).
    @Test func rotatingTheClubOrderPreservesPerClubCounts() {
        let cards = clubs.flatMap { abbr in
            (0..<3).map { i in
                ContentCard(
                    id: "\(abbr)-\(i)", layout: .blueskyTeamText, platform: .bluesky, placement: .feed,
                    sourceType: .club, teamAbbreviation: abbr, isLeague: false,
                    authorName: abbr, handle: nil, subreddit: nil, sourceName: nil,
                    title: "\(abbr)-\(i)", headline: nil, blurb: nil, bodyText: "b", thumbnailURL: nil,
                    duration: nil, igFallback: false, likes: nil, reposts: nil,
                    timestamp: Date(timeIntervalSince1970: 1_000_000 - Double(i) * 3600),
                    url: nil, ctaLabel: "View")
            }
        }
        var countsPerOffset: [[String: Int]] = []
        for offset in 0..<clubs.count {
            let order = ContentRoundRobin.rotate(clubs, by: offset)
            let out = FeedViewModel.arranged(cards, followedAbbreviations: order)
            var counts: [String: Int] = [:]
            for c in out { counts[c.teamAbbreviation ?? "?", default: 0] += 1 }
            countsPerOffset.append(counts)
        }
        // Same per-club counts at every offset — only the ORDER changed.
        #expect(countsPerOffset.allSatisfy { $0 == countsPerOffset[0] })
        #expect(Set(countsPerOffset[0].keys) == Set(clubs))
    }
}
