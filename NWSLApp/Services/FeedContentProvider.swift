//
//  FeedContentProvider.swift
//  NWSLApp
//
//  ⚠️ TEMP / SCAFFOLDING — curated static seed for the Feed tab, now emitting the
//  unified `ContentCard` model.
//
//  WHAT: the wider NWSL conversation — real beat reporters/outlets and real recent
//  storylines across ALL 16 clubs plus league-wide items, as the three Feed card
//  variants: reporter Bluesky posts (layout 4), news articles (layout 5), and
//  TikTok/IG clips surfaced via Reddit (layout 6). Coverage is deliberately even
//  so picking ANY team in onboarding surfaces a few listings. Posts paraphrase
//  real storylines for illustration; they are not verbatim quotes.
//
//  WHY: the Feed is "the world talking about your teams," but the app has no
//  content backend yet. This seed makes the tab real and testable across team
//  selections before the live pipeline (Bluesky AT Protocol + Reddit + news RSS,
//  team-tagged + filtered by a Haiku call in the proxy — Part-2 plan / What's-Next
//  #11) lands. The ViewModel/views don't change; only this provider does.
//
//  EDITORIAL POLICY: real soccer reporting only. The live pipeline moves that
//  filtering to the backend as a real gate (the "no hot takes" content rules).
//

import Foundation

struct FeedContentProvider {
    /// Returns the curated seed. Async to mirror the eventual networked source.
    func items() async -> [ContentCard] { Self.seed }

    /// Relative timestamps so "2h ago" stays sensible and the Feed's 7-day
    /// staleness window keeps the seed fresh while testing.
    private static func hoursAgo(_ h: Double) -> Date {
        Date().addingTimeInterval(-h * 3600)
    }

    // MARK: - Card builders (one per Feed layout)

    /// Layout 4 — a reporter Bluesky post. `abbr` tags the team it's about (nil +
    /// `league: true` for league-wide). A non-nil `mediaFrame` adds a media thumb.
    private static func reporter(
        _ id: String, _ name: String, _ handle: String, _ hours: Double,
        _ body: String, _ url: String,
        abbr: String? = nil, league: Bool = false,
        likes: Int, reposts: Int, mediaFrame: String? = nil
    ) -> ContentCard {
        ContentCard(
            id: id, layout: .blueskyReporter, platform: .bluesky, placement: .feed,
            teamAbbreviation: abbr, isLeague: league,
            authorName: name, handle: handle, subreddit: nil, sourceName: nil,
            title: nil, headline: nil, blurb: nil, bodyText: body,
            thumbnailURL: mediaFrame.flatMap(ContentCard.youTubeThumbnail), duration: nil, igFallback: false,
            likes: likes, reposts: reposts,
            timestamp: hoursAgo(hours),
            url: URL(string: url), ctaLabel: "View on Bluesky"
        )
    }

    /// Layout 5 — a news article (headline + blurb + link only). `thumbFrame` adds
    /// the optional 80×80 image.
    private static func article(
        _ id: String, _ outlet: String, _ hours: Double,
        _ headline: String, _ blurb: String, _ url: String,
        abbr: String? = nil, league: Bool = false, thumbFrame: String? = nil
    ) -> ContentCard {
        ContentCard(
            id: id, layout: .newsArticle, platform: .article, placement: .feed,
            teamAbbreviation: abbr, isLeague: league,
            authorName: nil, handle: nil, subreddit: nil, sourceName: outlet,
            title: nil, headline: headline, blurb: blurb, bodyText: nil,
            thumbnailURL: thumbFrame.flatMap(ContentCard.youTubeThumbnail), duration: nil, igFallback: false,
            likes: nil, reposts: nil,
            timestamp: hoursAgo(hours),
            url: URL(string: url), ctaLabel: "Read article"
        )
    }

    /// Layout 6 — a TikTok/IG clip surfaced through a subreddit (the cross-platform
    /// virals IG/X give no API for). `abbr` team-tags it for the follow filter.
    private static func social(
        _ id: String, _ platform: ContentCard.Platform, _ creator: String,
        _ subreddit: String, _ hours: Double, _ caption: String,
        _ mediaFrame: String, _ url: String, abbr: String? = nil
    ) -> ContentCard {
        ContentCard(
            id: id, layout: .socialVideo, platform: platform, placement: .feed,
            teamAbbreviation: abbr, isLeague: abbr == nil,
            authorName: creator, handle: nil, subreddit: subreddit, sourceName: nil,
            title: nil, headline: nil, blurb: nil, bodyText: caption,
            thumbnailURL: ContentCard.youTubeThumbnail(mediaFrame), duration: nil, igFallback: false,
            likes: nil, reposts: nil,
            timestamp: hoursAgo(hours),
            url: URL(string: url),
            ctaLabel: platform == .instagram ? "Open in Instagram" : "Open in TikTok"
        )
    }

    // Real reporter profile + outlet links (illustrative targets for the cards).
    private static let bskyMeg = "https://bsky.app/profile/meglinehan.com"
    private static let bskyJeff = "https://bsky.app/profile/jeffkassouf.bsky.social"
    private static let bskySteph = "https://bsky.app/profile/stephyang.bsky.social"
    private static let bskySandra = "https://bsky.app/profile/sandraherrera.bsky.social"
    private static let bskyJenna = "https://bsky.app/profile/jennatonelli.bsky.social"
    private static let bskyClaire = "https://bsky.app/profile/clairewatkins.bsky.social"
    private static let athletic = "https://www.nytimes.com/athletic/soccer/nwsl/"
    private static let espn = "https://www.espn.com/soccer/league/_/name/usa.nwsl"
    private static let equalizer = "https://equalizersoccer.com/"
    private static let jws = "https://justwomenssports.com/"
    private static let goal = "https://www.goal.com/en-us/category/nwsl"

    private static let seed: [ContentCard] = [
        // MARK: League-wide
        article("L1", "ESPN", 3,
                "NWSL Power Rankings: Utah holds top spot as Portland tumbles",
                "Where all 16 teams stand heading into the World Cup break.",
                espn, abbr: "UTA", league: true, thumbFrame: "4hsaTOQ1Myo"),
        reporter("L2", "Jeff Kassouf", "@jeffkassouf", 6,
                 "Reminder: the NWSL is on its World Cup break (June 1–27) while U.S. venues host the men's tournament. League play resumes late June.",
                 bskyJeff, league: true, likes: 421, reposts: 58),
        article("L3", "The Equalizer", 12,
                "NWSL stats and minutiae after Week 10",
                "The numbers that defined the final matchweek before the break.",
                equalizer, league: true),
        reporter("L4", "Meg Linehan", "@meglinehan.com", 20,
                 "Most NWSL players currently oppose a potential switch to the international calendar, per new reporting. The debate isn't going away.",
                 bskyMeg, league: true, likes: 933, reposts: 211),

        // MARK: Utah Royals
        reporter("UTA1", "Meg Linehan", "@meglinehan.com", 5,
                 "Utah Royals stretch their unbeaten run to 10 with a 2-2 draw at Portland. Top of the table into the break — quietly the story of the first half.",
                 bskyMeg, abbr: "UTA", likes: 612, reposts: 71),
        article("UTA2", "ESPN", 16,
                "Utah Royals' rise: inside the league's unlikely table-topper",
                "How a measured rebuild put the Royals on top of the NWSL standings.",
                espn, abbr: "UTA"),

        // MARK: Washington Spirit
        reporter("WAS1", "Steph Yang", "@stephyang", 4,
                 "Washington Spirit take care of Seattle 2-1 at home — six wins in their last seven. Looking like a genuine title contender again.",
                 bskySteph, abbr: "WAS", likes: 588, reposts: 64, mediaFrame: "IdSPrFaTxco"),
        article("WAS2", "The Athletic", 18,
                "Washington Spirit find their rhythm before the break",
                "A balanced attack has the Spirit among the East's form teams.",
                athletic, abbr: "WAS"),

        // MARK: Gotham FC
        reporter("GFC1", "Jeff Kassouf", "@jeffkassouf", 7,
                 "Gotham FC edge Houston 1-0 on a Jordynn Dudley goal — now unbeaten in six. Grinding out results even when they're not at their best.",
                 bskyJeff, abbr: "GFC", likes: 503, reposts: 49),
        article("GFC2", "The Equalizer", 26,
                "Gotham FC's unbeaten run is built on defense",
                "How NJ/NY has tightened up during its six-match streak.",
                equalizer, abbr: "GFC"),

        // MARK: San Diego Wave
        reporter("SD1", "Jenna Tonelli", "@jennatonelli", 8,
                 "San Diego Wave beat Chicago 2-0 to head into the break on top of the standings — and they still have Catarina Macario to fully integrate.",
                 bskyJenna, abbr: "SD", likes: 744, reposts: 88),
        article("SD2", "Just Women's Sports", 22,
                "San Diego Wave set the pace — with more to come",
                "The Wave lead the league, and Catarina Macario is just getting started.",
                jws, abbr: "SD"),

        // MARK: Kansas City Current
        reporter("KC1", "Sandra Herrera", "@sandraherrera", 9,
                 "Kansas City Current beat Boston 1-0 to push their home unbeaten run to a league-record 23. CPKC Stadium remains a fortress.",
                 bskySandra, abbr: "KC", likes: 821, reposts: 96),
        article("KC2", "ESPN", 30,
                "Kansas City's home dominance reaches record territory",
                "The Current extend the longest home unbeaten streak in NWSL history.",
                espn, abbr: "KC"),

        // MARK: North Carolina Courage
        reporter("NC1", "Claire Watkins", "@clairewatkins", 10,
                 "North Carolina Courage win 2-1 at Angel City, Ashley Sanchez pulling the strings in a dominant second half. Evelyn Ijeh's scored in three straight.",
                 bskyClaire, abbr: "NC", likes: 467, reposts: 53),
        article("NC2", "The Athletic", 33,
                "Ashley Sanchez is making the Courage tick",
                "A look at how NC's playmaker has elevated the attack.",
                athletic, abbr: "NC"),

        // MARK: Portland Thorns
        reporter("POR1", "Meg Linehan", "@meglinehan.com", 11,
                 "Sophia Wilson with a stoppage-time penalty to salvage a 2-2 draw for Portland against league-leading Utah. The Thorns keep finding ways to stay in games.",
                 bskyMeg, abbr: "POR", likes: 698, reposts: 80),
        article("POR2", "The Equalizer", 35,
                "Portland Thorns search for consistency after slipping in the table",
                "What's behind the Thorns' uneven first half of the season.",
                equalizer, abbr: "POR"),

        // MARK: Denver Summit
        reporter("DEN1", "Jeff Kassouf", "@jeffkassouf", 13,
                 "Denver Summit win 1-0 at Louisville — the expansion side keeps making life difficult on the road. Impressive for a first-year club.",
                 bskyJeff, abbr: "DEN", likes: 359, reposts: 41),
        article("DEN2", "Goal", 38,
                "Denver Summit's debut season is exceeding expectations",
                "The NWSL newcomer is holding its own against established sides.",
                goal, abbr: "DEN"),

        // MARK: Orlando Pride
        reporter("ORL1", "Steph Yang", "@stephyang", 14,
                 "Orlando Pride beat Bay 3-1 for their first back-to-back wins of 2026 — but Barbra Banda came off injured. That's the result they'll be watching.",
                 bskySteph, abbr: "ORL", likes: 612, reposts: 70),
        article("ORL2", "ESPN", 40,
                "Orlando Pride find form, but Banda injury clouds the win",
                "The Pride string wins together as they await news on Barbra Banda.",
                espn, abbr: "ORL"),

        // MARK: Seattle Reign
        reporter("SEA1", "Jenna Tonelli", "@jennatonelli", 15,
                 "Seattle Reign fall 2-1 at Washington. Midfield tweaks haven't unlocked the attack yet — finishing is the missing piece right now.",
                 bskyJenna, abbr: "SEA", likes: 288, reposts: 31),
        article("SEA2", "Just Women's Sports", 42,
                "Seattle Reign's attacking struggles continue",
                "Chances are coming; goals aren't. Inside the Reign's stalled offense.",
                jws, abbr: "SEA"),

        // MARK: Angel City
        reporter("LA1", "Sandra Herrera", "@sandraherrera", 17,
                 "Angel City drop another at home, 2-1 to North Carolina — now six losses in eight. A tough stretch for a side that started the season unbeaten.",
                 bskySandra, abbr: "LA", likes: 401, reposts: 47),
        article("LA2", "The Athletic", 44,
                "What's gone wrong for Angel City",
                "From an unbeaten start to a six-in-eight slide — unpacking ACFC's slump.",
                athletic, abbr: "LA"),

        // MARK: Boston Legacy
        reporter("BOS1", "Claire Watkins", "@clairewatkins", 19,
                 "Boston Legacy compact and organized but fall 1-0 at Kansas City — still winless through three. Competitive even without the results yet.",
                 bskyClaire, abbr: "BOS", likes: 233, reposts: 26),
        article("BOS2", "The Equalizer", 46,
                "Boston Legacy's growing pains in year one",
                "The expansion club is building an identity while chasing a first win.",
                equalizer, abbr: "BOS"),

        // MARK: Houston Dash
        reporter("HOU1", "Meg Linehan", "@meglinehan.com", 21,
                 "Houston Dash lose 1-0 at Gotham — just one win in their last eight. The margins keep going against them.",
                 bskyMeg, abbr: "HOU", likes: 318, reposts: 35),
        article("HOU2", "Goal", 48,
                "Houston Dash look to turn the corner after the break",
                "A rough run leaves the Dash searching for answers at the pause.",
                goal, abbr: "HOU"),

        // MARK: Bay FC
        reporter("BAY1", "Jeff Kassouf", "@jeffkassouf", 23,
                 "Bay FC fall 3-1 at Orlando — winless in five, with the goalkeeping under the spotlight. The break comes at a good time for the third-year club.",
                 bskyJeff, abbr: "BAY", likes: 277, reposts: 29),
        article("BAY2", "ESPN", 50,
                "Bay FC's defensive issues mount",
                "Goalkeeping questions and a winless run leave Bay with work to do.",
                espn, abbr: "BAY"),

        // MARK: Chicago Stars
        reporter("CHI1", "Steph Yang", "@stephyang", 25,
                 "Chicago Stars lose 2-0 at home to San Diego — a league-worst -19 goal difference now. A season to forget so far on the South Side.",
                 bskySteph, abbr: "CHI", likes: 244, reposts: 22),
        article("CHI2", "The Athletic", 52,
                "Chicago Stars hit the reset button at the break",
                "With the worst goal difference in the league, what comes next for Chicago.",
                athletic, abbr: "CHI"),

        // MARK: Racing Louisville
        reporter("LOU1", "Jenna Tonelli", "@jennatonelli", 27,
                 "Racing Louisville fall 1-0 to Denver — a third straight loss leaves them bottom of the table. The young roster is searching for a spark.",
                 bskyJenna, abbr: "LOU", likes: 198, reposts: 19),
        article("LOU2", "Just Women's Sports", 54,
                "Racing Louisville look for a turnaround from the bottom",
                "How Louisville plans to climb out of the basement after the break.",
                jws, abbr: "LOU"),

        // MARK: Social virals via Reddit (layout 6) — the cross-platform clips
        social("S1", .tiktok, "@trinityrodman", "NWSL", 7,
               "Trinity Rodman nutmeg into a no-look assist. She is operating on a different plane right now 😤 #NWSL",
               "IdSPrFaTxco", "https://www.tiktok.com/@trinityrodman", abbr: "WAS"),
        social("S2", .instagram, "@nwsl", "NWSL", 16,
               "Goal of the week? Sophia Wilson says hold my drink 🌹 (via @thornsfc)",
               "_37ruj00IQw", "https://www.instagram.com/nwsl/", abbr: "POR"),
        social("S3", .tiktok, "@kccurrent", "NWSL", 28,
               "Temwa Chawinga is just built different 🐆 23 unbeaten at home and counting.",
               "U0J32Tl9irA", "https://www.tiktok.com/@kccurrent", abbr: "KC"),
    ]
}
