//
//  ContentRoundRobinTests.swift
//  NWSLAppTests
//
//  The pure brains of Home Module 1's round-robin fair-share (QOL Change 1): every
//  followed team a guaranteed minimum, interleaved so a quiet club sits beside a loud
//  one, then chronological fill up to a follow-count-scaled cap. All deterministic, so
//  it tests like BracketScoring — fixed inputs, exact expected ordering.
//

import Foundation
import Testing
@testable import NWSLApp

struct ContentRoundRobinTests {

    /// A minimal Home-shaped card for team `abbr`, `secondsAgo` before a fixed epoch.
    /// Newer cards get LARGER timestamps. `id` doubles as the body for easy asserts.
    private func card(_ id: String, _ abbr: String, secondsAgo: Double,
                      layout: ContentCard.Layout = .youtube) -> ContentCard {
        ContentCard(
            id: id, layout: layout, platform: .youtube, placement: .home,
            teamAbbreviation: abbr, isLeague: false, authorName: abbr, handle: nil,
            subreddit: nil, sourceName: nil, title: id, headline: nil, blurb: nil,
            bodyText: nil, thumbnailURL: nil, duration: nil, igFallback: false,
            likes: nil, reposts: nil,
            timestamp: Date(timeIntervalSince1970: 1_000_000 - secondsAgo),
            url: nil, ctaLabel: "Watch"
        )
    }

    private func abbrs(_ result: ContentRoundRobin.Result) -> [String] {
        result.cards.compactMap(\.teamAbbreviation)
    }

    // MARK: - Tier table

    @Test func respectsTierTable() {
        #expect(ContentRoundRobin.tier(1).guaranteed == 4)
        #expect(ContentRoundRobin.tier(1).cap == 10)
        #expect(ContentRoundRobin.tier(2) == (4, 10))
        #expect(ContentRoundRobin.tier(3) == (3, 12))
        #expect(ContentRoundRobin.tier(4) == (3, 12))
        #expect(ContentRoundRobin.tier(5) == (2, 16))
        #expect(ContentRoundRobin.tier(7) == (2, 16))
        #expect(ContentRoundRobin.tier(8) == (2, 20))
        #expect(ContentRoundRobin.tier(12) == (2, 20))
    }

    // MARK: - Fair share

    @Test func quietTeamGetsGuaranteedSlotsAboveLoudTeam() {
        // A posts 10, B posts 2. Pure reverse-chron would bury B; fair-share must not.
        var cards: [ContentCard] = []
        for i in 0..<10 { cards.append(card("A\(i)", "A", secondsAgo: Double(i))) }      // A newest
        cards.append(card("B0", "B", secondsAgo: 100))
        cards.append(card("B1", "B", secondsAgo: 101))

        let result = ContentRoundRobin.balanced(cards: cards, followedAbbreviations: ["A", "B"])

        // Both of B's cards survive despite being older than all of A's.
        #expect(result.cards.contains { $0.id == "B0" })
        #expect(result.cards.contains { $0.id == "B1" })
        // Interleave puts B at the very top (index 1 — right after A's newest).
        #expect(result.cards[1].teamAbbreviation == "B")
        // tier(2) caps at 10; 12 eligible → 2 overflow.
        #expect(result.cards.count == 10)
        #expect(result.overflowCount == 2)
    }

    @Test func fillsRemainderChronologicallyAfterGuarantees() {
        // 2 teams, 6 each. Guarantee 4 each = 8 interleaved; cap 10 → 2 chronological fill.
        var cards: [ContentCard] = []
        for i in 0..<6 { cards.append(card("A\(i)", "A", secondsAgo: Double(i))) }
        for i in 0..<6 { cards.append(card("B\(i)", "B", secondsAgo: Double(i) + 0.5)) }

        let result = ContentRoundRobin.balanced(cards: cards, followedAbbreviations: ["A", "B"])

        #expect(result.cards.count == 10)
        #expect(result.overflowCount == 2)
        // The 2 fill slots are the newest leftovers (A4/B4 era), not the oldest.
        #expect(!result.cards.contains { $0.id == "A5" })
        #expect(!result.cards.contains { $0.id == "B5" })
    }

    @Test func capIsHardCeiling() {
        // 10 teams × 5 cards. tier(8+) caps at 20; reserved interleave alone hits it.
        var cards: [ContentCard] = []
        let teams = (0..<10).map { "T\($0)" }
        for t in teams {
            for i in 0..<5 { cards.append(card("\(t)-\(i)", t, secondsAgo: Double(i))) }
        }

        let result = ContentRoundRobin.balanced(cards: cards, followedAbbreviations: teams)

        #expect(result.cards.count == 20)
        #expect(result.overflowCount == 30)        // 50 eligible − 20 shown
        // Every team is represented (round 0 = one per team, all 10 fit under the cap).
        #expect(Set(abbrs(result)).count == 10)
    }

    @Test func deterministicAcrossRuns() {
        var cards: [ContentCard] = []
        for i in 0..<5 { cards.append(card("A\(i)", "A", secondsAgo: Double(i))) }
        for i in 0..<5 { cards.append(card("B\(i)", "B", secondsAgo: Double(i))) }   // tie timestamps across teams

        let first = ContentRoundRobin.balanced(cards: cards, followedAbbreviations: ["A", "B"])
        let second = ContentRoundRobin.balanced(cards: cards, followedAbbreviations: ["A", "B"])

        #expect(first.cards.map(\.id) == second.cards.map(\.id))
    }

    // MARK: - Rotation (pull-to-refresh window)

    @Test func rotateWrapsAround() {
        #expect(ContentRoundRobin.rotate([1, 2, 3], by: 0) == [1, 2, 3])
        #expect(ContentRoundRobin.rotate([1, 2, 3], by: 2) == [3, 1, 2])
        #expect(ContentRoundRobin.rotate([1, 2, 3], by: 3) == [1, 2, 3])   // full wrap
        #expect(ContentRoundRobin.rotate([1, 2, 3], by: 4) == [2, 3, 1])
    }

    @Test func advanceOffsetsShiftByPageAndWrap() {
        // 1 team, 3 cards, page size (guaranteed) 2 → 0 → 2 → 1 → 0 …
        var off = ContentRoundRobin.advancedOffsets(current: [:], availableCounts: ["A": 3], guaranteed: 2)
        #expect(off["A"] == 2)
        off = ContentRoundRobin.advancedOffsets(current: off, availableCounts: ["A": 3], guaranteed: 2)
        #expect(off["A"] == 1)
        off = ContentRoundRobin.advancedOffsets(current: off, availableCounts: ["A": 3], guaranteed: 2)
        #expect(off["A"] == 0)
    }

    @Test func rotationSurfacesUnseenCards() {
        // 5 teams (guaranteed 2). Team A has 4 cards; an offset of 2 should FEATURE its
        // 3rd-newest at the top instead of its newest — the "discover unseen" behavior.
        // (Everything fits under the cap of 16, so rotation changes ORDER, not which
        // cards appear; the featured/top card is the visible signal.)
        var cards: [ContentCard] = []
        for i in 0..<4 { cards.append(card("A\(i)", "A", secondsAgo: Double(i))) }   // A0 newest … A3 oldest
        for t in ["B", "C", "D", "E"] { cards.append(card("\(t)0", t, secondsAgo: 1)) }

        let teams = ["A", "B", "C", "D", "E"]   // A leads the round-robin interleave
        let base = ContentRoundRobin.balanced(cards: cards, followedAbbreviations: teams)
        let rotated = ContentRoundRobin.balanced(cards: cards, followedAbbreviations: teams,
                                                 windowOffsets: ["A": 2])

        // The featured (top) card is A's reserved[0]: A0 at offset 0, A2 at offset 2.
        #expect(base.cards.first?.id == "A0")
        #expect(rotated.cards.first?.id == "A2")
        // Rotation lifts A2 above A0 (A0 falls from a reserved slot to the fill tail).
        let a0 = rotated.cards.firstIndex { $0.id == "A0" }
        let a2 = rotated.cards.firstIndex { $0.id == "A2" }
        #expect(a2! < a0!)
    }

    // MARK: - Type variety within a team (bug #4)

    @Test func teamSlotsMixContentTypesNotJustVideos() {
        // A team with a flood of videos + one older news article. The news must land
        // in the team's guaranteed slots (not be buried under the newer clips), so
        // Home stays a varied feed rather than a video channel.
        var cards: [ContentCard] = []
        for i in 0..<10 { cards.append(card("V\(i)", "A", secondsAgo: Double(i), layout: .youtube)) }
        cards.append(card("NEWS", "A", secondsAgo: 100, layout: .newsArticle))   // older than all videos

        let result = ContentRoundRobin.balanced(cards: cards, followedAbbreviations: ["A"])

        // tier(1) guarantees 4; with type-interleaving the news sits at slot 1
        // (newest video, then the one news article).
        #expect(result.cards.first?.id == "V0")
        #expect(result.cards.count >= 2)
        #expect(result.cards[1].id == "NEWS")
    }

    @Test func typeInterleavedIsNoOpForSingleType() {
        let cards = (0..<5).map { card("V\($0)", "A", secondsAgo: Double($0)) }   // all youtube
        #expect(ContentRoundRobin.typeInterleaved(cards).map(\.id) == cards.map(\.id))
    }
}
