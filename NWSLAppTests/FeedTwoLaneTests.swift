//
//  FeedTwoLaneTests.swift
//  NWSLAppTests
//
//  The Feed's pure two-lane arrangement (`FeedViewModel.arrange`): a followed club's OWN
//  posts get an EQUAL count-based share (volume-blind, age-agnostic), while league-wide
//  voices (reporters / league / news / players — no per-club team) ride a separate
//  chronological lane that's capped + woven in so it can never push club content below
//  its fair share. No time window. Deterministic, so it tests like ContentRoundRobin.
//

import Foundation
import Testing
@testable import NWSLApp

struct FeedTwoLaneTests {

    /// A Feed-shaped card. `source` sets the class; club cards carry `abbr`, league-wide
    /// voices (reporter/league/news/player) carry none. Newer → larger timestamp.
    private func card(_ id: String, source: ContentCard.SourceType, abbr: String? = nil,
                      secondsAgo: Double) -> ContentCard {
        let layout: ContentCard.Layout
        switch source {
        case .club:     layout = .blueskyTeamText
        case .reporter: layout = .blueskyReporter
        case .news:     layout = .newsArticle
        case .player:   layout = .socialVideo
        case .league:   layout = .blueskyReporter
        }
        return ContentCard(
            id: id, layout: layout, platform: .bluesky, placement: .feed,
            sourceType: source, teamAbbreviation: abbr, isLeague: abbr == nil,
            authorName: abbr ?? id, handle: nil, subreddit: nil, sourceName: nil,
            title: id, headline: nil, blurb: nil, bodyText: id, thumbnailURL: nil,
            duration: nil, igFallback: false, likes: nil, reposts: nil,
            timestamp: Date(timeIntervalSince1970: 1_000_000 - secondsAgo),
            url: nil, ctaLabel: "View"
        )
    }

    private func ids(_ cards: [ContentCard]) -> [String] { cards.map(\.id) }

    @Test func clubsGetEqualShareRegardlessOfVolume() {
        // A (chatty) posts 30 club cards, B (quiet) posts 2. No league voices.
        var cards: [ContentCard] = []
        for i in 0..<30 { cards.append(card("A\(i)", source: .club, abbr: "A", secondsAgo: Double(i))) }
        cards.append(card("B0", source: .club, abbr: "B", secondsAgo: 500))
        cards.append(card("B1", source: .club, abbr: "B", secondsAgo: 501))

        let result = FeedViewModel.arrange(cards, followedAbbreviations: ["A", "B"])

        // feedSlotsPerClub(2) == 12 → A capped at 12, B keeps both. A never buries B.
        #expect(result.filter { $0.teamAbbreviation == "A" }.count == 12)
        #expect(result.filter { $0.teamAbbreviation == "B" }.count == 2)
        #expect(result[1].teamAbbreviation == "B")   // B at the top, beside A
    }

    @Test func leagueVoicesCappedAtClubCountAndWovenIn() {
        // 2 club cards (1 each) + many reporter/news cards. League is capped at the club
        // count (2) and woven in — it can't dominate.
        var cards: [ContentCard] = [
            card("A0", source: .club, abbr: "A", secondsAgo: 10),
            card("B0", source: .club, abbr: "B", secondsAgo: 11),
        ]
        for i in 0..<8 { cards.append(card("R\(i)", source: .reporter, secondsAgo: Double(i))) }

        let result = FeedViewModel.arrange(cards, followedAbbreviations: ["A", "B"])

        let clubShown = result.filter { $0.teamAbbreviation != nil }.count
        let leagueShown = result.filter { $0.teamAbbreviation == nil }.count
        #expect(clubShown == 2)
        #expect(leagueShown == 2)                 // capped at the club count, not 8
        // Club content leads the first cycle (2 club : 1 league cadence).
        #expect(result[0].teamAbbreviation != nil)
        #expect(result[1].teamAbbreviation != nil)
    }

    @Test func leagueOnlyFeedStaysChronological() {
        // No followed-club posts (e.g. the Reporters chip) → pure chronological league.
        var cards: [ContentCard] = []
        for i in 0..<5 { cards.append(card("R\(i)", source: .reporter, secondsAgo: Double(i))) }

        let result = FeedViewModel.arrange(cards, followedAbbreviations: ["A", "B"])

        #expect(ids(result) == ["R0", "R1", "R2", "R3", "R4"])   // newest-first, untouched
    }

    @Test func clubOnlyFeedIsJustTheBalancedClubs() {
        // No league voices (e.g. the Clubs chip) → just the balanced club lane.
        let cards = [
            card("A0", source: .club, abbr: "A", secondsAgo: 1),
            card("B0", source: .club, abbr: "B", secondsAgo: 2),
        ]
        let result = FeedViewModel.arrange(cards, followedAbbreviations: ["A", "B"])
        #expect(Set(ids(result)) == ["A0", "B0"])
        #expect(result.allSatisfy { $0.teamAbbreviation != nil })
    }

    @Test func ageAgnosticOldClubPostStillSurfaces() {
        // B's only post is ancient; it still surfaces (no time window).
        let cards = [
            card("A0", source: .club, abbr: "A", secondsAgo: 1),
            card("B0", source: .club, abbr: "B", secondsAgo: 300_000_000),   // ~10 years
        ]
        let result = FeedViewModel.arrange(cards, followedAbbreviations: ["A", "B"])
        #expect(result.contains { $0.id == "B0" })
    }
}
