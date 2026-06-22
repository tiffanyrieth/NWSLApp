//
//  FeedBalancingTests.swift
//  NWSLAppTests
//
//  The Social tab uses the SAME single per-club balance as Home (`FeedViewModel.arranged`):
//  every team-tagged card — club, news, reporter, player, league — balances per
//  `teamAbbreviation`, volume-blind and age-agnostic (no two-lane, no time window). The
//  proxy team-tags ~all Social cards; the rare genuinely team-less card is appended, never
//  capped or laned. Deterministic, so it tests like ContentRoundRobin.
//

import Foundation
import Testing
@testable import NWSLApp

struct FeedBalancingTests {

    /// A Feed-shaped card. `source` sets the class; `abbr` nil = a genuinely league-wide
    /// (team-less) card. Newer → larger timestamp.
    private func card(_ id: String, source: ContentCard.SourceType, abbr: String?,
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

    @Test func allSourceTypesBalancePerClubNotJustClubPosts() {
        // Club A has a heavy reporter/news week; club B is quiet. The earlier two-lane bug
        // let A's non-club cards crowd B. Now every type balances per club.
        var cards: [ContentCard] = []
        for i in 0..<10 { cards.append(card("A-rep\(i)", source: .reporter, abbr: "A", secondsAgo: Double(i))) }
        for i in 0..<10 { cards.append(card("A-news\(i)", source: .news, abbr: "A", secondsAgo: 100 + Double(i))) }
        cards.append(card("B-player0", source: .player, abbr: "B", secondsAgo: 500))
        cards.append(card("B-club0", source: .club, abbr: "B", secondsAgo: 501))

        let result = FeedViewModel.arranged(cards, followedAbbreviations: ["A", "B"])

        // feedSlotsPerClub(2) == 12 → A capped at 12, B keeps both; B is not buried.
        #expect(result.filter { $0.teamAbbreviation == "A" }.count == 12)
        #expect(result.filter { $0.teamAbbreviation == "B" }.count == 2)
        #expect(result[1].teamAbbreviation == "B")   // B sits at the top beside A
    }

    @Test func volumeEarnsNothingExtra() {
        // 40 cards from A vs 2 from B → A capped at its equal allowance, B intact.
        var cards: [ContentCard] = []
        for i in 0..<40 { cards.append(card("A\(i)", source: .reporter, abbr: "A", secondsAgo: Double(i))) }
        cards.append(card("B0", source: .club, abbr: "B", secondsAgo: 900))
        cards.append(card("B1", source: .news, abbr: "B", secondsAgo: 901))

        let result = FeedViewModel.arranged(cards, followedAbbreviations: ["A", "B"])
        #expect(result.filter { $0.teamAbbreviation == "A" }.count == 12)
        #expect(result.filter { $0.teamAbbreviation == "B" }.count == 2)
    }

    @Test func teamlessLeagueCardAppendedNotCapped() {
        // The lone genuinely team-less card rides at the end — never a lane or a cap, even
        // though it's the newest item.
        let cards: [ContentCard] = [
            card("A0", source: .club, abbr: "A", secondsAgo: 5),
            card("B0", source: .club, abbr: "B", secondsAgo: 6),
            card("LEAGUE-wide", source: .league, abbr: nil, secondsAgo: 1),   // newest, but team-less
        ]

        let result = FeedViewModel.arranged(cards, followedAbbreviations: ["A", "B"])
        #expect(result.contains { $0.id == "LEAGUE-wide" })
        #expect(result.last?.id == "LEAGUE-wide")          // appended after the balanced clubs
        #expect(result.filter { $0.teamAbbreviation != nil }.count == 2)
    }

    @Test func ageAgnosticOldClubCardStillSurfaces() {
        // The balance (`arranged`) itself is age-blind; recency is a separate pre-filter
        // (`isFresh`) applied only to third-party voices — see the tests below.
        let cards = [
            card("A0", source: .reporter, abbr: "A", secondsAgo: 1),
            card("B0", source: .club, abbr: "B", secondsAgo: 300_000_000),   // ~10 years
        ]
        let result = FeedViewModel.arranged(cards, followedAbbreviations: ["A", "B"])
        #expect(result.contains { $0.id == "B0" })
    }

    @Test func recencyDropsStaleThirdPartyKeepsOwnContent() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let day = 24.0 * 60 * 60
        // Third-party voices (reporter / league / news): 30-day cutoff.
        #expect( FeedViewModel.isFresh(card("rep-fresh",  source: .reporter, abbr: "A", secondsAgo: 29 * day), now: now))
        #expect(!FeedViewModel.isFresh(card("rep-stale",  source: .reporter, abbr: "A", secondsAgo: 31 * day), now: now))
        #expect(!FeedViewModel.isFresh(card("news-stale", source: .news,     abbr: "A", secondsAgo: 31 * day), now: now))
        #expect(!FeedViewModel.isFresh(card("lg-stale",   source: .league,   abbr: nil, secondsAgo: 40 * day), now: now))
        // The user's OWN followed content (club / player): age-agnostic.
        #expect( FeedViewModel.isFresh(card("club-old",   source: .club,     abbr: "A", secondsAgo: 365 * day), now: now))
        #expect( FeedViewModel.isFresh(card("player-old", source: .player,   abbr: "A", secondsAgo: 200 * day), now: now))
    }
}
