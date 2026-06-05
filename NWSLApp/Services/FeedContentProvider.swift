//
//  FeedContentProvider.swift
//  NWSLApp
//
//  ⚠️ TEMP / SCAFFOLDING — curated static seed for the Feed tab.
//
//  WHAT: A curated set of Feed items drawn from real NWSL beat reporters/outlets
//  and real, recent storylines, covering ALL 16 clubs (a few items each) plus a
//  few league-wide items. Coverage is deliberately league-wide and even — NOT
//  skewed to any particular club — so picking ANY team in onboarding surfaces a
//  few relevant listings for a demo. Posts paraphrase real storylines for
//  illustration; they are not verbatim quotes.
//
//  WHY: The Feed tab is "the world talking about your teams" — reporter posts and
//  news links — but the app has no content backend yet. This seed lets the tab be
//  fully functional and realistic for concept demos and for testing how the Feed
//  looks across different team selections, per the design spec's call to "seed
//  with real reporter accounts and test in a closed environment before shipping."
//
//  WHEN REMOVED: Replace `items()` with a real source — a social/news aggregator
//  or the planned caching proxy — returning the same `[FeedItem]`. Per-post team
//  tagging (which team[s] a post is about) is the hard part with live content;
//  see CLAUDE.md What's-Next for the proxy + lightweight-AI tagging plan. The
//  ViewModel/views don't change; only this provider does.
//
//  EDITORIAL POLICY (per the spec's "Editorial filtering" section): content is
//  real soccer reporting only. When this becomes a live pipeline, that filtering
//  moves here or to the backend as a real gate.
//

import Foundation

struct FeedContentProvider {
    /// Returns the curated seed. Async to mirror the eventual networked source,
    /// even though today it resolves immediately.
    func items() async -> [FeedItem] { Self.seed }

    // MARK: - Team tags (one per club; the per-team-filter join key)

    private static let la  = FeedTeamTag(abbreviation: "LA")    // Angel City FC
    private static let bay = FeedTeamTag(abbreviation: "BAY")   // Bay FC
    private static let bos = FeedTeamTag(abbreviation: "BOS")   // Boston Legacy FC
    private static let chi = FeedTeamTag(abbreviation: "CHI")   // Chicago Stars FC
    private static let den = FeedTeamTag(abbreviation: "DEN")   // Denver Summit FC
    private static let gfc = FeedTeamTag(abbreviation: "GFC")   // Gotham FC
    private static let hou = FeedTeamTag(abbreviation: "HOU")   // Houston Dash
    private static let kc  = FeedTeamTag(abbreviation: "KC")    // Kansas City Current
    private static let nc  = FeedTeamTag(abbreviation: "NC")    // North Carolina Courage
    private static let orl = FeedTeamTag(abbreviation: "ORL")   // Orlando Pride
    private static let por = FeedTeamTag(abbreviation: "POR")   // Portland Thorns FC
    private static let lou = FeedTeamTag(abbreviation: "LOU")   // Racing Louisville FC
    private static let sd  = FeedTeamTag(abbreviation: "SD")    // San Diego Wave FC
    private static let sea = FeedTeamTag(abbreviation: "SEA")   // Seattle Reign FC
    private static let uta = FeedTeamTag(abbreviation: "UTA")   // Utah Royals
    private static let was = FeedTeamTag(abbreviation: "WAS")   // Washington Spirit

    /// Timestamps are relative to "now" so the "2h ago" labels stay sensible
    /// while testing (this is seed data, not a frozen snapshot).
    private static func hoursAgo(_ h: Double) -> Date {
        Date().addingTimeInterval(-h * 3600)
    }

    // Convenience builders to keep the seed list readable.
    private static func post(
        _ id: String, _ source: String, _ handle: String, _ platform: String,
        _ hours: Double, _ body: String, _ url: String,
        teams: [FeedTeamTag], league: Bool = false
    ) -> FeedItem {
        FeedItem(id: id, kind: .reporterPost, sourceName: source, sourceHandle: handle,
                 platform: platform, timestamp: hoursAgo(hours), headline: nil, summary: nil,
                 body: body, url: URL(string: url), teams: teams, isLeague: league)
    }

    private static func article(
        _ id: String, _ outlet: String, _ hours: Double,
        _ headline: String, _ summary: String, _ url: String,
        teams: [FeedTeamTag], league: Bool = false
    ) -> FeedItem {
        FeedItem(id: id, kind: .articleLink, sourceName: outlet, sourceHandle: nil,
                 platform: outlet, timestamp: hoursAgo(hours), headline: headline, summary: summary,
                 body: nil, url: URL(string: url), teams: teams, isLeague: league)
    }

    // Real reporter profile + outlet links (illustrative targets for the cards).
    private static let bskyMeg   = "https://bsky.app/profile/meglinehan.com"
    private static let bskyJeff  = "https://bsky.app/profile/jeffkassouf.bsky.social"
    private static let bskySteph = "https://bsky.app/profile/stephyang.bsky.social"
    private static let bskySandra = "https://bsky.app/profile/sandraherrera.bsky.social"
    private static let bskyJenna = "https://bsky.app/profile/jennatonelli.bsky.social"
    private static let bskyClaire = "https://bsky.app/profile/clairewatkins.bsky.social"
    private static let athletic = "https://www.nytimes.com/athletic/soccer/nwsl/"
    private static let espn = "https://www.espn.com/soccer/league/_/name/usa.nwsl"
    private static let equalizer = "https://equalizersoccer.com/"
    private static let jws = "https://justwomenssports.com/"
    private static let goal = "https://www.goal.com/en-us/category/nwsl"

    private static let seed: [FeedItem] = [
        // MARK: League-wide
        article("L1", "ESPN", 3,
                "NWSL Power Rankings: Utah holds top spot as Portland tumbles",
                "Where all 16 teams stand heading into the World Cup break.",
                espn, teams: [uta, por], league: true),
        post("L2", "Jeff Kassouf", "@jeffkassouf", "Bluesky", 6,
             "Reminder: the NWSL is on its World Cup break (June 1–27) while U.S. venues host the men's tournament. League play resumes late June.",
             bskyJeff, teams: [], league: true),
        article("L3", "The Equalizer", 12,
                "NWSL stats and minutiae after Week 10",
                "The numbers that defined the final matchweek before the break.",
                equalizer, teams: [], league: true),
        post("L4", "Meg Linehan", "@meglinehan.com", "Bluesky", 20,
             "Most NWSL players currently oppose a potential switch to the international calendar, per new reporting. The debate isn't going away.",
             bskyMeg, teams: [], league: true),

        // MARK: Utah Royals
        post("UTA1", "Meg Linehan", "@meglinehan.com", "Bluesky", 5,
             "Utah Royals stretch their unbeaten run to 10 with a 2-2 draw at Portland. Top of the table into the break — quietly the story of the first half.",
             bskyMeg, teams: [uta]),
        article("UTA2", "ESPN", 16,
                "Utah Royals' rise: inside the league's unlikely table-topper",
                "How a measured rebuild put the Royals on top of the NWSL standings.",
                espn, teams: [uta]),

        // MARK: Washington Spirit
        post("WAS1", "Steph Yang", "@stephyang", "Bluesky", 4,
             "Washington Spirit take care of Seattle 2-1 at home — six wins in their last seven. Looking like a genuine title contender again.",
             bskySteph, teams: [was]),
        article("WAS2", "The Athletic", 18,
                "Washington Spirit find their rhythm before the break",
                "A balanced attack has the Spirit among the East's form teams.",
                athletic, teams: [was]),

        // MARK: Gotham FC
        post("GFC1", "Jeff Kassouf", "@jeffkassouf", "Bluesky", 7,
             "Gotham FC edge Houston 1-0 on a Jordynn Dudley goal — now unbeaten in six. Grinding out results even when they're not at their best.",
             bskyJeff, teams: [gfc]),
        article("GFC2", "The Equalizer", 26,
                "Gotham FC's unbeaten run is built on defense",
                "How NJ/NY has tightened up during its six-match streak.",
                equalizer, teams: [gfc]),

        // MARK: San Diego Wave
        post("SD1", "Jenna Tonelli", "@jennatonelli", "Bluesky", 8,
             "San Diego Wave beat Chicago 2-0 to head into the break on top of the standings — and they still have Catarina Macario to fully integrate.",
             bskyJenna, teams: [sd]),
        article("SD2", "Just Women's Sports", 22,
                "San Diego Wave set the pace — with more to come",
                "The Wave lead the league, and Catarina Macario is just getting started.",
                jws, teams: [sd]),

        // MARK: Kansas City Current
        post("KC1", "Sandra Herrera", "@sandraherrera", "Bluesky", 9,
             "Kansas City Current beat Boston 1-0 to push their home unbeaten run to a league-record 23. CPKC Stadium remains a fortress.",
             bskySandra, teams: [kc]),
        article("KC2", "ESPN", 30,
                "Kansas City's home dominance reaches record territory",
                "The Current extend the longest home unbeaten streak in NWSL history.",
                espn, teams: [kc]),

        // MARK: North Carolina Courage
        post("NC1", "Claire Watkins", "@clairewatkins", "Bluesky", 10,
             "North Carolina Courage win 2-1 at Angel City, Ashley Sanchez pulling the strings in a dominant second half. Evelyn Ijeh's scored in three straight.",
             bskyClaire, teams: [nc]),
        article("NC2", "The Athletic", 33,
                "Ashley Sanchez is making the Courage tick",
                "A look at how NC's playmaker has elevated the attack.",
                athletic, teams: [nc]),

        // MARK: Portland Thorns
        post("POR1", "Meg Linehan", "@meglinehan.com", "Bluesky", 11,
             "Sophia Wilson with a stoppage-time penalty to salvage a 2-2 draw for Portland against league-leading Utah. The Thorns keep finding ways to stay in games.",
             bskyMeg, teams: [por]),
        article("POR2", "The Equalizer", 35,
                "Portland Thorns search for consistency after slipping in the table",
                "What's behind the Thorns' uneven first half of the season.",
                equalizer, teams: [por]),

        // MARK: Denver Summit
        post("DEN1", "Jeff Kassouf", "@jeffkassouf", "Bluesky", 13,
             "Denver Summit win 1-0 at Louisville — the expansion side keeps making life difficult on the road. Impressive for a first-year club.",
             bskyJeff, teams: [den]),
        article("DEN2", "Goal", 38,
                "Denver Summit's debut season is exceeding expectations",
                "The NWSL newcomer is holding its own against established sides.",
                goal, teams: [den]),

        // MARK: Orlando Pride
        post("ORL1", "Steph Yang", "@stephyang", "Bluesky", 14,
             "Orlando Pride beat Bay 3-1 for their first back-to-back wins of 2026 — but Barbra Banda came off injured. That's the result they'll be watching.",
             bskySteph, teams: [orl]),
        article("ORL2", "ESPN", 40,
                "Orlando Pride find form, but Banda injury clouds the win",
                "The Pride string wins together as they await news on Barbra Banda.",
                espn, teams: [orl]),

        // MARK: Seattle Reign
        post("SEA1", "Jenna Tonelli", "@jennatonelli", "Bluesky", 15,
             "Seattle Reign fall 2-1 at Washington. Midfield tweaks haven't unlocked the attack yet — finishing is the missing piece right now.",
             bskyJenna, teams: [sea]),
        article("SEA2", "Just Women's Sports", 42,
                "Seattle Reign's attacking struggles continue",
                "Chances are coming; goals aren't. Inside the Reign's stalled offense.",
                jws, teams: [sea]),

        // MARK: Angel City
        post("LA1", "Sandra Herrera", "@sandraherrera", "Bluesky", 17,
             "Angel City drop another at home, 2-1 to North Carolina — now six losses in eight. A tough stretch for a side that started the season unbeaten.",
             bskySandra, teams: [la]),
        article("LA2", "The Athletic", 44,
                "What's gone wrong for Angel City",
                "From an unbeaten start to a six-in-eight slide — unpacking ACFC's slump.",
                athletic, teams: [la]),

        // MARK: Boston Legacy
        post("BOS1", "Claire Watkins", "@clairewatkins", "Bluesky", 19,
             "Boston Legacy compact and organized but fall 1-0 at Kansas City — still winless through three. Competitive even without the results yet.",
             bskyClaire, teams: [bos]),
        article("BOS2", "The Equalizer", 46,
                "Boston Legacy's growing pains in year one",
                "The expansion club is building an identity while chasing a first win.",
                equalizer, teams: [bos]),

        // MARK: Houston Dash
        post("HOU1", "Meg Linehan", "@meglinehan.com", "Bluesky", 21,
             "Houston Dash lose 1-0 at Gotham — just one win in their last eight. The margins keep going against them.",
             bskyMeg, teams: [hou]),
        article("HOU2", "Goal", 48,
                "Houston Dash look to turn the corner after the break",
                "A rough run leaves the Dash searching for answers at the pause.",
                goal, teams: [hou]),

        // MARK: Bay FC
        post("BAY1", "Jeff Kassouf", "@jeffkassouf", "Bluesky", 23,
             "Bay FC fall 3-1 at Orlando — winless in five, with the goalkeeping under the spotlight. The break comes at a good time for the third-year club.",
             bskyJeff, teams: [bay]),
        article("BAY2", "ESPN", 50,
                "Bay FC's defensive issues mount",
                "Goalkeeping questions and a winless run leave Bay with work to do.",
                espn, teams: [bay]),

        // MARK: Chicago Stars
        post("CHI1", "Steph Yang", "@stephyang", "Bluesky", 25,
             "Chicago Stars lose 2-0 at home to San Diego — a league-worst -19 goal difference now. A season to forget so far on the South Side.",
             bskySteph, teams: [chi]),
        article("CHI2", "The Athletic", 52,
                "Chicago Stars hit the reset button at the break",
                "With the worst goal difference in the league, what comes next for Chicago.",
                athletic, teams: [chi]),

        // MARK: Racing Louisville
        post("LOU1", "Jenna Tonelli", "@jennatonelli", "Bluesky", 27,
             "Racing Louisville fall 1-0 to Denver — a third straight loss leaves them bottom of the table. The young roster is searching for a spark.",
             bskyJenna, teams: [lou]),
        article("LOU2", "Just Women's Sports", 54,
                "Racing Louisville look for a turnaround from the bottom",
                "How Louisville plans to climb out of the basement after the break.",
                jws, teams: [lou]),
    ]
}
