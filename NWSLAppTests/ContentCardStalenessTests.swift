//
//  ContentCardStalenessTests.swift
//  NWSLAppTests
//
//  Verifies the `[ContentCard].fresh(_:)` staleness floor — the rule that keeps a
//  surface from going sparse during a slow content stretch (an international break,
//  the off-season). Both Home and the Feed carry a floor of 6: when fewer than 6
//  cards fall inside the age window, `fresh` relaxes to the 6 most-recent regardless
//  of age, so the tab never reads as "broken/empty" when it's just quiet.
//

import Foundation
import Testing
@testable import NWSLApp

struct ContentCardStalenessTests {

    /// One minimal Feed-shaped card at `daysAgo` before `now`.
    private func card(_ id: String, daysAgo: Double, now: Date) -> ContentCard {
        ContentCard(
            id: id, layout: .blueskyReporter, platform: .bluesky, placement: .feed,
            teamAbbreviation: nil, isLeague: true, authorName: "Reporter", handle: "@r",
            subreddit: nil, sourceName: nil, title: nil, headline: nil, blurb: nil,
            bodyText: id, thumbnailURL: nil, duration: nil, igFallback: false,
            likes: nil, reposts: nil,
            timestamp: now.addingTimeInterval(-daysAgo * 86_400),
            url: nil, ctaLabel: "View on Bluesky"
        )
    }

    @Test func feedRelaxesToFloorWhenWindowIsSparse() {
        let now = Date()
        // Only 2 posts inside the 7-day window; 5 well outside it.
        var cards = [card("fresh-a", daysAgo: 1, now: now),
                     card("fresh-b", daysAgo: 4, now: now)]
        for i in 0..<5 { cards.append(card("old-\(i)", daysAgo: Double(20 + i), now: now)) }

        let result = cards.fresh(.feed, now: now)

        // Window alone would yield 2; the floor of 6 relaxes it to the 6 newest.
        #expect(result.count == 6)
        // And it is the *most-recent* 6 — the oldest card (day 24) is excluded.
        #expect(!result.contains { $0.id == "old-4" })
        #expect(result.contains { $0.id == "fresh-a" })
    }

    @Test func feedKeepsStrictWindowWhenEnoughAreFresh() {
        let now = Date()
        // 8 posts all inside the 7-day window (days 0…7).
        let cards = (0..<8).map { card("f-\($0)", daysAgo: Double($0), now: now) }

        let result = cards.fresh(.feed, now: now)

        // The floor never truncates — it only relaxes when sparse. All 8 stay.
        #expect(result.count == 8)
    }

    @Test func feedFloorDoesNotInventCardsBeyondWhatExists() {
        let now = Date()
        // Only 3 cards exist at all, none in-window.
        let cards = (0..<3).map { card("x-\($0)", daysAgo: Double(30 + $0), now: now) }

        let result = cards.fresh(.feed, now: now)

        // prefix(6) of 3 → 3, not a crash or padding.
        #expect(result.count == 3)
    }
}
