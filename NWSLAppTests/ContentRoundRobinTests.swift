//
//  ContentRoundRobinTests.swift
//  NWSLAppTests
//
//  The pure brains of the count-based, volume-blind fair-share shared by Home Module 1
//  and the Feed club lane: each followed club gets an EQUAL slot allowance of its
//  most-recent posts (age-agnostic), interleaved one-per-club so a quiet club sits
//  beside a loud one. A chatty club can never exceed its allowance or steal a quieter
//  club's slot — there is no time window and no volume-rewarding chronological fill.
//  All deterministic, so it tests like BracketScoring — fixed inputs, exact ordering.
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

    // MARK: - Per-club allowance tables

    @Test func homeSlotsPerClubTable() {
        #expect(ContentRoundRobin.homeSlotsPerClub(1) == 12)   // one club → full preview
        #expect(ContentRoundRobin.homeSlotsPerClub(2) == 6)
        #expect(ContentRoundRobin.homeSlotsPerClub(3) == 4)
        #expect(ContentRoundRobin.homeSlotsPerClub(4) == 4)
        #expect(ContentRoundRobin.homeSlotsPerClub(5) == 3)
        #expect(ContentRoundRobin.homeSlotsPerClub(7) == 3)
        #expect(ContentRoundRobin.homeSlotsPerClub(8) == 2)
        #expect(ContentRoundRobin.homeSlotsPerClub(16) == 2)
    }

    @Test func feedSlotsPerClubTable() {
        #expect(ContentRoundRobin.feedSlotsPerClub(1) == 12)
        #expect(ContentRoundRobin.feedSlotsPerClub(2) == 12)
        #expect(ContentRoundRobin.feedSlotsPerClub(4) == 8)
        #expect(ContentRoundRobin.feedSlotsPerClub(7) == 6)
        #expect(ContentRoundRobin.feedSlotsPerClub(8) == 4)
    }

    // MARK: - Fair share (count-based, volume-blind, age-agnostic)

    @Test func quietClubSurvivesAndSitsBesideLoudClub() {
        // A posts 10, B posts 2 (all older than A's). Pure reverse-chron would bury B.
        var cards: [ContentCard] = []
        for i in 0..<10 { cards.append(card("A\(i)", "A", secondsAgo: Double(i))) }      // A newest
        cards.append(card("B0", "B", secondsAgo: 100))
        cards.append(card("B1", "B", secondsAgo: 101))

        let result = ContentRoundRobin.balanced(
            cards: cards, followedAbbreviations: ["A", "B"], slotsPerClub: 6)

        // Both of B's older cards survive.
        #expect(result.cards.contains { $0.id == "B0" })
        #expect(result.cards.contains { $0.id == "B1" })
        // Interleave puts B at the very top (index 1 — right after A's newest).
        #expect(result.cards[1].teamAbbreviation == "B")
        // A capped at its allowance (6), B shows its 2 → 8 shown, 12 eligible → 4 overflow.
        #expect(result.cards.filter { $0.teamAbbreviation == "A" }.count == 6)
        #expect(result.cards.filter { $0.teamAbbreviation == "B" }.count == 2)
        #expect(result.cards.count == 8)
        #expect(result.overflowCount == 4)
    }

    @Test func volumeEarnsNothingExtra() {
        // The LinkedIn failure mode: a club relisting all day must NOT bury a quiet one.
        // A posts 40 this week, B posts 2. Each gets the SAME allowance; A can't exceed it
        // and can't take B's slots.
        var cards: [ContentCard] = []
        for i in 0..<40 { cards.append(card("A\(i)", "A", secondsAgo: Double(i))) }
        cards.append(card("B0", "B", secondsAgo: 500))
        cards.append(card("B1", "B", secondsAgo: 501))

        let result = ContentRoundRobin.balanced(
            cards: cards, followedAbbreviations: ["A", "B"], slotsPerClub: 6)

        #expect(result.cards.filter { $0.teamAbbreviation == "A" }.count == 6)   // capped at allowance
        #expect(result.cards.filter { $0.teamAbbreviation == "B" }.count == 2)   // all of B's, intact
        #expect(result.overflowCount == 34)                                      // 42 − 8
    }

    @Test func ageAgnosticSilentClubStillSurfaces() {
        // B hasn't posted in "years" (huge secondsAgo). Its most-recent posts still
        // surface as its fair share — no time window drops them.
        var cards: [ContentCard] = []
        for i in 0..<3 { cards.append(card("A\(i)", "A", secondsAgo: Double(i))) }
        cards.append(card("B0", "B", secondsAgo: 300_000_000))   // ~10 years old
        cards.append(card("B1", "B", secondsAgo: 300_000_100))

        let result = ContentRoundRobin.balanced(
            cards: cards, followedAbbreviations: ["A", "B"], slotsPerClub: 6)

        #expect(result.cards.contains { $0.id == "B0" })
        #expect(result.cards.contains { $0.id == "B1" })
    }

    @Test func eachClubLimitedToItsEqualAllowance() {
        // 10 clubs × 5 cards, allowance 2 → every club contributes exactly 2 (no cap
        // games, no volume bonus): 20 shown, 30 overflow, all 10 represented.
        var cards: [ContentCard] = []
        let teams = (0..<10).map { "T\($0)" }
        for t in teams {
            for i in 0..<5 { cards.append(card("\(t)-\(i)", t, secondsAgo: Double(i))) }
        }

        let result = ContentRoundRobin.balanced(
            cards: cards, followedAbbreviations: teams, slotsPerClub: 2)

        #expect(result.cards.count == 20)
        #expect(result.overflowCount == 30)        // 50 eligible − 20 shown
        #expect(Set(abbrs(result)).count == 10)    // every club represented
        for t in teams {
            #expect(result.cards.filter { $0.teamAbbreviation == t }.count == 2)
        }
    }

    @Test func deterministicAcrossRuns() {
        var cards: [ContentCard] = []
        for i in 0..<5 { cards.append(card("A\(i)", "A", secondsAgo: Double(i))) }
        for i in 0..<5 { cards.append(card("B\(i)", "B", secondsAgo: Double(i))) }   // tie timestamps across teams

        let first = ContentRoundRobin.balanced(
            cards: cards, followedAbbreviations: ["A", "B"], slotsPerClub: 6)
        let second = ContentRoundRobin.balanced(
            cards: cards, followedAbbreviations: ["A", "B"], slotsPerClub: 6)

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
        // 1 team, 3 cards, page size 2 → 0 → 2 → 1 → 0 …
        var off = ContentRoundRobin.advancedOffsets(current: [:], availableCounts: ["A": 3], pageSize: 2)
        #expect(off["A"] == 2)
        off = ContentRoundRobin.advancedOffsets(current: off, availableCounts: ["A": 3], pageSize: 2)
        #expect(off["A"] == 1)
        off = ContentRoundRobin.advancedOffsets(current: off, availableCounts: ["A": 3], pageSize: 2)
        #expect(off["A"] == 0)
    }

    @Test func rotationSurfacesUnseenCards() {
        // 5 teams (allowance 3). Team A has 4 cards; an offset of 2 should FEATURE its
        // 3rd-newest at the top instead of its newest — the "discover unseen" behavior.
        var cards: [ContentCard] = []
        for i in 0..<4 { cards.append(card("A\(i)", "A", secondsAgo: Double(i))) }   // A0 newest … A3 oldest
        for t in ["B", "C", "D", "E"] { cards.append(card("\(t)0", t, secondsAgo: 1)) }

        let teams = ["A", "B", "C", "D", "E"]   // A leads the round-robin interleave
        let base = ContentRoundRobin.balanced(
            cards: cards, followedAbbreviations: teams, slotsPerClub: 3)
        let rotated = ContentRoundRobin.balanced(
            cards: cards, followedAbbreviations: teams, slotsPerClub: 3, windowOffsets: ["A": 2])

        // The featured (top) card is A's slot[0]: A0 at offset 0, A2 at offset 2.
        #expect(base.cards.first?.id == "A0")
        #expect(rotated.cards.first?.id == "A2")
        // Rotation lifts A2 above A0 within A's slots.
        let a0 = rotated.cards.firstIndex { $0.id == "A0" }
        let a2 = rotated.cards.firstIndex { $0.id == "A2" }
        #expect(a2! < a0!)
    }

    // MARK: - Type variety within a club's slots

    @Test func clubSlotsMixContentTypesNotJustVideos() {
        // A club with a flood of videos + one older news article. The news must land in
        // the club's slots (not be buried under newer clips), so the feed stays varied.
        var cards: [ContentCard] = []
        for i in 0..<10 { cards.append(card("V\(i)", "A", secondsAgo: Double(i), layout: .youtube)) }
        cards.append(card("NEWS", "A", secondsAgo: 100, layout: .newsArticle))   // older than all videos

        let result = ContentRoundRobin.balanced(
            cards: cards, followedAbbreviations: ["A"], slotsPerClub: 12)

        // Type-interleaving puts the news at slot 1 (newest video, then the article).
        #expect(result.cards.first?.id == "V0")
        #expect(result.cards.count >= 2)
        #expect(result.cards[1].id == "NEWS")
    }

    @Test func typeInterleavedIsNoOpForSingleType() {
        let cards = (0..<5).map { card("V\($0)", "A", secondsAgo: Double($0)) }   // all youtube
        #expect(ContentRoundRobin.typeInterleaved(cards).map(\.id) == cards.map(\.id))
    }
}
