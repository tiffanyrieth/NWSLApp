//
//  TeamContentProvider.swift
//  NWSLApp
//
//  ⚠️ TEMP / SCAFFOLDING — curated static seed for Home's Module 1 ("From your
//  teams"), now emitting the unified `ContentCard` model.
//
//  WHAT: each club's own voice. Two REAL, recent videos per club (all 16) from the
//  team's official YouTube channel — verified 2026 ids, so the card loads the real
//  thumbnail (img.youtube.com/vi/{id}/…) and the tap opens the actual video — PLUS,
//  for a few marquee clubs, varied Bluesky text/media, a team-tagged social clip,
//  and an Instagram-fallback post, so every Home card variant (layouts 1·2·3·6·7)
//  is reviewable in the simulator before any live source is wired.
//
//  WHY: Module 1 is the spec's hook — "content sweeps you in like an IG post."
//  The app has no content backend yet, so this hand-picked seed makes the module
//  fully functional and realistic, mirroring how FeedContentProvider seeds the Feed.
//
//  WHEN REMOVED: replace `items()` with the live YouTube/Bluesky/Reddit pipeline —
//  proxy routes returning `[ContentCard]` (see the Part-2 plan + CLAUDE.md
//  What's-Next #11). The async signature is already shaped for it; the VM/views
//  don't change. DEBUG `-useSeedContent` keeps this as a fallback after that lands.
//
//  CURATION RULE (YouTube): pick LANDSCAPE (16:9) videos, not vertical Shorts —
//  YouTube bakes a Short into the 4:3 hqdefault.jpg with pillarbox bars, so it
//  renders narrow in the wide thumbnail box. All ids below are verified landscape.
//

import Foundation

struct TeamContentProvider {
    /// Returns the curated seed. Async to mirror the eventual networked source,
    /// even though today it resolves immediately.
    func items() async -> [ContentCard] { Self.seed }

    /// Timestamps are relative to "now" so "2h ago" stays sensible and the Home
    /// 72h staleness window keeps the seed fresh while testing.
    private static func hoursAgo(_ h: Double) -> Date {
        Date().addingTimeInterval(-h * 3600)
    }

    // MARK: - Card builders (one per Home layout)

    /// Layout 1 — a YouTube video. Thumbnail + tap both derive from `videoID`.
    private static func youtube(
        _ id: String, _ abbr: String, _ hours: Double,
        title: String, videoID: String, duration: String
    ) -> ContentCard {
        ContentCard(
            id: id, layout: .youtube, platform: .youtube, placement: .home,
            teamAbbreviation: abbr, isLeague: false,
            authorName: nil, handle: nil, subreddit: nil, sourceName: nil,
            title: title, headline: nil, blurb: nil, bodyText: nil,
            thumbnailURL: ContentCard.youTubeThumbnail(videoID), duration: duration, igFallback: false,
            likes: nil, reposts: nil,
            timestamp: hoursAgo(hours),
            url: URL(string: "https://www.youtube.com/watch?v=\(videoID)"),
            ctaLabel: "Watch on YouTube"
        )
    }

    /// Layout 2/3 — a team Bluesky post (text, or with a media frame). A non-nil
    /// `mediaFrame` (a YouTube id reused as a stand-in image) makes it layout 3.
    private static func teamPost(
        _ id: String, _ abbr: String, _ hours: Double,
        team: String, handle: String, body: String,
        likes: Int, reposts: Int, url: String, mediaFrame: String? = nil
    ) -> ContentCard {
        ContentCard(
            id: id, layout: mediaFrame == nil ? .blueskyTeamText : .blueskyTeamMedia,
            platform: .bluesky, placement: .home,
            teamAbbreviation: abbr, isLeague: false,
            authorName: team, handle: handle, subreddit: nil, sourceName: nil,
            title: nil, headline: nil, blurb: nil, bodyText: body,
            thumbnailURL: mediaFrame.flatMap(ContentCard.youTubeThumbnail), duration: nil, igFallback: false,
            likes: likes, reposts: reposts,
            timestamp: hoursAgo(hours),
            url: URL(string: url), ctaLabel: "View on Bluesky"
        )
    }

    /// Layout 6 — a team-tagged TikTok/IG clip surfaced via Reddit (placement
    /// `.both`, so it can also appear in the Feed's Social filter).
    private static func socialClip(
        _ id: String, _ abbr: String, _ hours: Double,
        platform: ContentCard.Platform, creator: String, subreddit: String,
        caption: String, mediaFrame: String, url: String
    ) -> ContentCard {
        ContentCard(
            id: id, layout: .socialVideo, platform: platform, placement: .both,
            teamAbbreviation: abbr, isLeague: false,
            authorName: creator, handle: nil, subreddit: subreddit, sourceName: nil,
            title: nil, headline: nil, blurb: nil, bodyText: caption,
            thumbnailURL: ContentCard.youTubeThumbnail(mediaFrame), duration: nil, igFallback: false,
            likes: nil, reposts: nil,
            timestamp: hoursAgo(hours),
            url: URL(string: url),
            ctaLabel: platform == .instagram ? "Open in Instagram" : "Open in TikTok"
        )
    }

    /// Layout 7 — a team Instagram post with no usable thumbnail → the IG fallback
    /// strip (Instagram has no public API for a frame, so a real pipeline lands here).
    private static func igFallbackPost(
        _ id: String, _ abbr: String, _ hours: Double,
        team: String, caption: String, url: String
    ) -> ContentCard {
        ContentCard(
            id: id, layout: .instagramFallback, platform: .instagram, placement: .home,
            teamAbbreviation: abbr, isLeague: false,
            authorName: team, handle: nil, subreddit: nil, sourceName: nil,
            title: nil, headline: nil, blurb: nil, bodyText: caption,
            thumbnailURL: nil, duration: nil, igFallback: true,
            likes: nil, reposts: nil,
            timestamp: hoursAgo(hours),
            url: URL(string: url), ctaLabel: "Open in Instagram"
        )
    }

    // Real, recent landscape videos from each club's official YouTube channel
    // (verified 2026 season), plus extra variants for marquee clubs so all five
    // Home card layouts render. All timestamps are inside the 72h Home window.
    private static let seed: [ContentCard] = [
        // MARK: Angel City FC
        youtube("LA-1", "LA", 5, title: "Match Highlights | Angel City FC vs North Carolina Courage", videoID: "bs3r9AbiAxk", duration: "10:00"),
        youtube("LA-2", "LA", 14, title: "GOAL: Maiara Niehues vs North Carolina Courage", videoID: "xGDZWan6up4", duration: "1:00"),

        // MARK: Bay FC
        youtube("BAY-1", "BAY", 8, title: "Caroline Conti STRIKES against Orlando Pride", videoID: "FCt8ZY3xocY", duration: "0:34"),
        youtube("BAY-2", "BAY", 21, title: "Full Highlights | Bay FC at Orlando Pride", videoID: "iYm5ormS9qA", duration: "9:51"),

        // MARK: Boston Legacy FC
        youtube("BOS-1", "BOS", 3, title: "Postgame Press Conference vs. Seattle Reign FC", videoID: "fnwgebaTb9k", duration: "15:30"),
        youtube("BOS-2", "BOS", 18, title: "Postgame Press Conference: May 12, 2026", videoID: "XUKe1GDMDhg", duration: "12:54"),

        // MARK: Chicago Stars FC
        youtube("CHI-1", "CHI", 7, title: "Is it a Star? The squad plays our categories game 🌟", videoID: "dLiMB5XM8U4", duration: "1:05"),
        youtube("CHI-2", "CHI", 26, title: "Match Highlights | Chicago Stars FC @ Bay FC", videoID: "0OyyhjYaTOo", duration: "5:01"),

        // MARK: Denver Summit FC
        youtube("DEN-1", "DEN", 4, title: "A behind-the-scenes look at training with our GK union 👀", videoID: "p0cvf5-1h3Y", duration: "1:30"),
        youtube("DEN-2", "DEN", 16, title: "Our first-ever signing scoring her first goal for Denver 🤩", videoID: "3okXVjSj5IE", duration: "0:13"),

        // MARK: Gotham FC (+ Bluesky text, IG fallback)
        youtube("GFC-1", "GFC", 6, title: "A decade of Mandy Freeman 🗽", videoID: "xx8slc-q3s0", duration: "11:01"),
        youtube("GFC-2", "GFC", 19, title: "Extended Match Highlights: Gotham FC 1, Houston Dash 0", videoID: "leMYHlckK2I", duration: "10:00"),
        teamPost("GFC-3", "GFC", 9, team: "Gotham FC", handle: "@gothamfc.bsky.social",
                 body: "SIX unbeaten and counting. 1–0 over Houston on the road — Jordynn Dudley with the winner. Grinding out results. 🖤",
                 likes: 842, reposts: 76, url: "https://bsky.app/profile/gothamfc.bsky.social"),
        igFallbackPost("GFC-4", "GFC", 22, team: "Gotham FC",
                       caption: "Matchday looks 🔥 Swipe for the full kit reveal before tonight's clash under the lights.",
                       url: "https://www.instagram.com/gothamfc/"),

        // MARK: Houston Dash
        youtube("HOU-1", "HOU", 9, title: "All Angles | Kat Rader's precise strike", videoID: "khgdvraSRkY", duration: "0:22"),
        youtube("HOU-2", "HOU", 30, title: "Jane Campbell reflects on 200 appearances", videoID: "1dnzKA8NghA", duration: "2:24"),

        // MARK: Kansas City Current (+ Bluesky media, social clip)
        youtube("KC-1", "KC", 5, title: "Mic'd Up: Chiefs Rookies at the KC Current Match", videoID: "cJMSF_oajX0", duration: "1:36"),
        youtube("KC-2", "KC", 23, title: "\"I Am Loved\" | Katie Scott", videoID: "U0J32Tl9irA", duration: "1:52"),
        teamPost("KC-3", "KC", 11, team: "Kansas City Current", handle: "@kccurrent.bsky.social",
                 body: "23 straight unbeaten at home — a league record. CPKC remains a fortress. 💙",
                 likes: 1531, reposts: 188, url: "https://bsky.app/profile/kccurrent.bsky.social",
                 mediaFrame: "cJMSF_oajX0"),
        socialClip("KC-5", "KC", 15, platform: .tiktok, creator: "@kccurrent", subreddit: "NWSL",
                   caption: "Temwa Chawinga's first touch is just unfair 🤯 #NWSL #KCCurrent",
                   mediaFrame: "U0J32Tl9irA", url: "https://www.tiktok.com/@kccurrent"),

        // MARK: North Carolina Courage
        youtube("NC-1", "NC", 10, title: "The Courage Within with Ally Schlegel", videoID: "j5NcGy3_WQc", duration: "2:39"),
        youtube("NC-2", "NC", 28, title: "Highlights: NC Courage vs. Racing Louisville", videoID: "02r9b1w6fg0", duration: "0:34"),

        // MARK: Orlando Pride (+ Bluesky media)
        youtube("ORL-1", "ORL", 6, title: "Sights & Sounds | Orlando Pride vs Bay FC", videoID: "gxFfPHB0hxU", duration: "1:36"),
        youtube("ORL-2", "ORL", 22, title: "Highlights | Orlando Pride 3, Bay FC 1", videoID: "esVAz-OG1Kw", duration: "9:51"),
        teamPost("ORL-3", "ORL", 13, team: "Orlando Pride", handle: "@orlandopride.bsky.social",
                 body: "Back-to-back wins for the first time in 2026! 3–1 over Bay. The purple wall held. 💜",
                 likes: 967, reposts: 102, url: "https://bsky.app/profile/orlandopride.bsky.social",
                 mediaFrame: "esVAz-OG1Kw"),

        // MARK: Portland Thorns FC (+ Bluesky text, social clip)
        youtube("POR-1", "POR", 7, title: "The Recap: Thorns avenge loss to San Diego at home", videoID: "_37ruj00IQw", duration: "3:14"),
        youtube("POR-2", "POR", 25, title: "Match Highlights | Thorns vs Utah Royals FC", videoID: "De-4nGTGuqM", duration: "10:01"),
        teamPost("POR-3", "POR", 8, team: "Portland Thorns FC", handle: "@thorns.bsky.social",
                 body: "Sophia Wilson. Stoppage time. Ice in her veins. 2–2 at home against the league leaders. 🌹",
                 likes: 1284, reposts: 161, url: "https://bsky.app/profile/thorns.bsky.social"),
        socialClip("POR-5", "POR", 17, platform: .instagram, creator: "@thornsfc", subreddit: "NWSL",
                   caption: "The wall at Providence Park before kickoff gives me chills every single time 🌹",
                   mediaFrame: "_37ruj00IQw", url: "https://www.instagram.com/thornsfc/"),

        // MARK: Racing Louisville FC
        youtube("LOU-1", "LOU", 11, title: "Racing's 'goldfish mentality' | Emma Sears & Kayla Fischer", videoID: "h_upJQCPFDU", duration: "6:53"),
        youtube("LOU-2", "LOU", 33, title: "Highlights: Denver Summit FC 1, Racing Louisville FC 0", videoID: "axHx4nTSHEc", duration: "9:59"),

        // MARK: San Diego Wave FC
        youtube("SD-1", "SD", 4, title: "Wave Sounds | 2-0 Win at Chicago Stars FC", videoID: "qI3vFXoOEQk", duration: "4:33"),
        youtube("SD-2", "SD", 20, title: "Highlights | San Diego Wave FC at Chicago Stars FC", videoID: "Gr5RS9q3o90", duration: "10:00"),

        // MARK: Seattle Reign FC
        youtube("SEA-1", "SEA", 8, title: "GOAL: Maddie Mercado forces a Spirit own goal", videoID: "1JwgDxClwPA", duration: "0:59"),
        youtube("SEA-2", "SEA", 27, title: "Highlights: Seattle Reign at Washington Spirit", videoID: "TuC9lhkY9nw", duration: "15:00"),

        // MARK: Utah Royals
        youtube("UTA-1", "UTA", 5, title: "Utah Royals vs Utah City Names!", videoID: "CzlPKyGe1eI", duration: "1:45"),
        youtube("UTA-2", "UTA", 24, title: "URFC Match Highlights: May 30, 2026", videoID: "4hsaTOQ1Myo", duration: "3:41"),

        // MARK: Washington Spirit (+ Bluesky text, IG fallback)
        youtube("WAS-1", "WAS", 3, title: "The fastest brace in NWSL history! 🥳", videoID: "IdSPrFaTxco", duration: "0:29"),
        youtube("WAS-2", "WAS", 17, title: "Spirit vs Reign Match Highlights", videoID: "0jsXURRN0U0", duration: "10:06"),
        teamPost("WAS-3", "WAS", 6, team: "Washington Spirit", handle: "@washspirit.bsky.social",
                 body: "Six wins in seven. The Spirit are flying into the break. Take a bow, everyone. ❤️🤍",
                 likes: 1102, reposts: 134, url: "https://bsky.app/profile/washspirit.bsky.social"),
        igFallbackPost("WAS-4", "WAS", 20, team: "Washington Spirit",
                       caption: "Trinity Rodman matchday energy ⚡️ See you all at Audi Field.",
                       url: "https://www.instagram.com/washspirit/"),
    ]
}
