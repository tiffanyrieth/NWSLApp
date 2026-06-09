//
//  TeamContentProvider.swift
//  NWSLApp
//
//  ⚠️ TEMP / SCAFFOLDING — curated static seed for Home's Module 1 ("From your
//  teams").
//
//  WHAT: 2 content items per club (all 16) — each a REAL, recent video from the
//  team's OWN official YouTube channel (verified for the 2026 season, incl. the
//  Denver Summit / Boston Legacy expansion sides and the Chicago Stars rebrand).
//  Every item carries the real `youTubeVideoID`, so the card loads the real
//  YouTube thumbnail (img.youtube.com/vi/{id}/…) and the tap opens the actual
//  video. Captions are the videos' real titles, lightly cleaned (sponsor tags /
//  HTML entities trimmed).
//
//  WHY: Module 1 is the spec's hook — "content sweeps you in like an IG post."
//  The app has no content backend yet, so this hand-picked seed lets the module
//  be fully functional and realistic for concept demos and for testing how Home
//  looks across different team selections, mirroring how FeedContentProvider
//  seeds the Feed tab.
//
//  WHEN REMOVED: Replace `items()` with a real source — a team-channel aggregator
//  (YouTube Data API / IG Graph / Bluesky firehose) or the planned caching proxy
//  — returning the same `[TeamContentItem]`. The async signature is already shaped
//  for it; the ViewModel/views don't change. A live source would refresh this set
//  continuously instead of pinning these specific videos.
//
//  NOTE: these are a fixed snapshot of real videos. They won't rotate or expire
//  on their own; if a team deletes a video its thumbnail 404s and the card falls
//  back to the designed crest tile (see TeamContentCard). Re-curate when stale.
//
//  CURATION RULE: pick LANDSCAPE (16:9) videos, not vertical Shorts. YouTube bakes
//  a Short into the 4:3 `hqdefault.jpg` with black pillarbox bars, so it renders as
//  a narrow, non-filling image in the card's wide thumbnail box. (The card can't
//  fix this — the bars are part of the image pixels.) All ids below are verified
//  landscape.
//

import Foundation

struct TeamContentProvider {
    /// Returns the curated seed. Async to mirror the eventual networked source,
    /// even though today it resolves immediately.
    func items() async -> [TeamContentItem] { Self.seed }

    /// Timestamps are relative to "now" so the "2h ago" labels stay sensible while
    /// testing (this is seed data, not a frozen snapshot).
    private static func hoursAgo(_ h: Double) -> Date {
        Date().addingTimeInterval(-h * 3600)
    }

    /// Builds a YouTube content item. The tap URL and the thumbnail are both
    /// derived from `videoID`, so the seed only needs the real id + real title +
    /// real duration.
    private static func video(
        _ id: String, _ abbr: String, _ hours: Double,
        caption: String, videoID: String, duration: String
    ) -> TeamContentItem {
        TeamContentItem(
            id: id, teamAbbreviation: abbr, platform: .youtube,
            timestamp: hoursAgo(hours), caption: caption,
            durationLabel: duration,
            url: URL(string: "https://www.youtube.com/watch?v=\(videoID)"),
            youTubeVideoID: videoID
        )
    }

    // Real, recent videos from each club's official YouTube channel (verified
    // 2026 season). ids/titles/durations pulled live from each channel's feed.
    private static let seed: [TeamContentItem] = [
        // Angel City FC
        video("LA-1", "LA", 5, caption: "Match Highlights | Angel City FC vs North Carolina Courage", videoID: "bs3r9AbiAxk", duration: "10:00"),
        video("LA-2", "LA", 14, caption: "GOAL: Maiara Niehues vs North Carolina Courage", videoID: "xGDZWan6up4", duration: "1:00"),

        // Bay FC
        video("BAY-1", "BAY", 8, caption: "Caroline Conti STRIKES against Orlando Pride", videoID: "FCt8ZY3xocY", duration: "0:34"),
        video("BAY-2", "BAY", 21, caption: "Full Highlights | Bay FC at Orlando Pride", videoID: "iYm5ormS9qA", duration: "9:51"),

        // Boston Legacy FC — expansion side; its landscape catalog is press
        // conferences (features/recaps are vertical Shorts that pillarbox in the
        // 4:3 thumbnail). Pressers fill the 16:9 card cleanly.
        video("BOS-1", "BOS", 3, caption: "Postgame Press Conference vs. Seattle Reign FC", videoID: "fnwgebaTb9k", duration: "15:30"),
        video("BOS-2", "BOS", 18, caption: "Postgame Press Conference: May 12, 2026", videoID: "XUKe1GDMDhg", duration: "12:54"),

        // Chicago Stars FC
        video("CHI-1", "CHI", 7, caption: "Is it a Star? The squad plays our categories game 🌟", videoID: "dLiMB5XM8U4", duration: "1:05"),
        video("CHI-2", "CHI", 26, caption: "Match Highlights | Chicago Stars FC @ Bay FC", videoID: "0OyyhjYaTOo", duration: "5:01"),

        // Denver Summit FC
        video("DEN-1", "DEN", 4, caption: "A behind-the-scenes look at training with our GK union 👀", videoID: "p0cvf5-1h3Y", duration: "1:30"),
        video("DEN-2", "DEN", 16, caption: "Our first-ever signing scoring her first goal for Denver 🤩", videoID: "3okXVjSj5IE", duration: "0:13"),

        // Gotham FC
        video("GFC-1", "GFC", 6, caption: "A decade of Mandy Freeman 🗽", videoID: "xx8slc-q3s0", duration: "11:01"),
        video("GFC-2", "GFC", 19, caption: "Extended Match Highlights: Gotham FC 1, Houston Dash 0", videoID: "leMYHlckK2I", duration: "10:00"),

        // Houston Dash
        video("HOU-1", "HOU", 9, caption: "All Angles | Kat Rader's precise strike", videoID: "khgdvraSRkY", duration: "0:22"),
        video("HOU-2", "HOU", 30, caption: "Jane Campbell reflects on 200 appearances", videoID: "1dnzKA8NghA", duration: "2:24"),

        // Kansas City Current
        video("KC-1", "KC", 5, caption: "Mic'd Up: Chiefs Rookies at the KC Current Match", videoID: "cJMSF_oajX0", duration: "1:36"),
        video("KC-2", "KC", 23, caption: "\"I Am Loved\" | Katie Scott", videoID: "U0J32Tl9irA", duration: "1:52"),

        // North Carolina Courage
        video("NC-1", "NC", 10, caption: "The Courage Within with Ally Schlegel", videoID: "j5NcGy3_WQc", duration: "2:39"),
        video("NC-2", "NC", 28, caption: "Highlights: NC Courage vs. Racing Louisville", videoID: "02r9b1w6fg0", duration: "0:34"),

        // Orlando Pride
        video("ORL-1", "ORL", 6, caption: "Sights & Sounds | Orlando Pride vs Bay FC", videoID: "gxFfPHB0hxU", duration: "1:36"),
        video("ORL-2", "ORL", 22, caption: "Highlights | Orlando Pride 3, Bay FC 1", videoID: "esVAz-OG1Kw", duration: "9:51"),

        // Portland Thorns FC
        video("POR-1", "POR", 7, caption: "The Recap: Thorns avenge loss to San Diego at home", videoID: "_37ruj00IQw", duration: "3:14"),
        video("POR-2", "POR", 25, caption: "Match Highlights | Thorns vs Utah Royals FC", videoID: "De-4nGTGuqM", duration: "10:01"),

        // Racing Louisville FC
        video("LOU-1", "LOU", 11, caption: "Racing's 'goldfish mentality' | Emma Sears & Kayla Fischer", videoID: "h_upJQCPFDU", duration: "6:53"),
        video("LOU-2", "LOU", 33, caption: "Highlights: Denver Summit FC 1, Racing Louisville FC 0", videoID: "axHx4nTSHEc", duration: "9:59"),

        // San Diego Wave FC
        video("SD-1", "SD", 4, caption: "Wave Sounds | 2-0 Win at Chicago Stars FC", videoID: "qI3vFXoOEQk", duration: "4:33"),
        video("SD-2", "SD", 20, caption: "Highlights | San Diego Wave FC at Chicago Stars FC", videoID: "Gr5RS9q3o90", duration: "10:00"),

        // Seattle Reign FC
        video("SEA-1", "SEA", 8, caption: "GOAL: Maddie Mercado forces a Spirit own goal", videoID: "1JwgDxClwPA", duration: "0:59"),
        video("SEA-2", "SEA", 27, caption: "Highlights: Seattle Reign at Washington Spirit", videoID: "TuC9lhkY9nw", duration: "15:00"),

        // Utah Royals
        video("UTA-1", "UTA", 5, caption: "Utah Royals vs Utah City Names!", videoID: "CzlPKyGe1eI", duration: "1:45"),
        video("UTA-2", "UTA", 24, caption: "URFC Match Highlights: May 30, 2026", videoID: "4hsaTOQ1Myo", duration: "3:41"),

        // Washington Spirit
        video("WAS-1", "WAS", 3, caption: "The fastest brace in NWSL history! 🥳", videoID: "IdSPrFaTxco", duration: "0:29"),
        video("WAS-2", "WAS", 17, caption: "Spirit vs Reign Match Highlights", videoID: "0jsXURRN0U0", duration: "10:06"),
    ]
}
