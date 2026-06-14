//
//  HomeContentFilterTests.swift
//  NWSLAppTests
//
//  The Home content-type chip classifier (QOL Change 3). Mirrors the Feed's
//  All/News/Social split but adds Videos — and deliberately diverges on social video
//  clips: on Home a clip is a Video; on the Feed it's Social. This pins that contract.
//

import Foundation
import Testing
@testable import NWSLApp

struct HomeContentFilterTests {

    /// A card with a given layout; nothing else matters for classification.
    private func card(_ layout: ContentCard.Layout) -> ContentCard {
        ContentCard(
            id: layout.rawValue, layout: layout, platform: .youtube, placement: .home,
            teamAbbreviation: "WAS", isLeague: false, authorName: nil, handle: nil,
            subreddit: nil, sourceName: nil, title: nil, headline: nil, blurb: nil,
            bodyText: nil, thumbnailURL: nil, duration: nil, igFallback: false,
            likes: nil, reposts: nil, timestamp: Date(), url: nil, ctaLabel: "Open"
        )
    }

    @Test func allPassesEverything() {
        let everyLayout: [ContentCard.Layout] = [
            .youtube, .blueskyTeamText, .blueskyTeamMedia, .blueskyReporter,
            .newsArticle, .socialVideo, .instagramFallback,
        ]
        for layout in everyLayout {
            #expect(ContentRoundRobin.passes(card(layout), filter: .all))
        }
    }

    @Test func videosAreYouTubeAndSocialClips() {
        #expect(ContentRoundRobin.passes(card(.youtube), filter: .videos))
        #expect(ContentRoundRobin.passes(card(.socialVideo), filter: .videos))
        #expect(!ContentRoundRobin.passes(card(.newsArticle), filter: .videos))
        #expect(!ContentRoundRobin.passes(card(.blueskyTeamText), filter: .videos))
    }

    @Test func newsIsArticlesOnly() {
        #expect(ContentRoundRobin.passes(card(.newsArticle), filter: .news))
        #expect(!ContentRoundRobin.passes(card(.youtube), filter: .news))
        #expect(!ContentRoundRobin.passes(card(.blueskyReporter), filter: .news))
    }

    @Test func socialExcludesVideoClipUnlikeFeed() {
        // The deliberate divergence: a social video is a Video on Home, NOT Social.
        #expect(!ContentRoundRobin.passes(card(.socialVideo), filter: .social))
        // The conversational/text voices ARE social.
        #expect(ContentRoundRobin.passes(card(.blueskyTeamText), filter: .social))
        #expect(ContentRoundRobin.passes(card(.blueskyTeamMedia), filter: .social))
        #expect(ContentRoundRobin.passes(card(.blueskyReporter), filter: .social))
        #expect(ContentRoundRobin.passes(card(.instagramFallback), filter: .social))
        #expect(!ContentRoundRobin.passes(card(.youtube), filter: .social))
    }

    @Test func everyFilterHasALabel() {
        for filter in HomeContentFilter.allCases {
            #expect(!filter.label.isEmpty)
        }
    }
}
