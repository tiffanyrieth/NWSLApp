//
//  TeamContentProvider.swift
//  NWSLApp
//
//  ⚠️ TEMP / SCAFFOLDING — curated static seed for Home's Module 1 ("From your
//  teams").
//
//  WHAT: ~2 content items per club (all 16) representing each team's OWN channels
//  — official YouTube, Instagram, TikTok, Bluesky. Every `url` is a REAL, durable
//  account-level link (the team's actual channel/profile, verified for the 2026
//  season incl. the Denver Summit / Boston Legacy expansion sides). Captions
//  paraphrase the kind of content these accounts post (matchday hype, player
//  features, behind-the-scenes, community) — they are illustrative, not scraped
//  posts.
//
//  WHY: Module 1 is the spec's hook — "content sweeps you in like an IG post."
//  The app has no content backend yet, so this seed lets the module be fully
//  functional and realistic for concept demos and for testing how Home looks
//  across different team selections, mirroring how FeedContentProvider seeds the
//  Feed tab.
//
//  WHEN REMOVED: Replace `items()` with a real source — a team-channel aggregator
//  (YouTube Data API / IG Graph / Bluesky firehose) or the planned caching proxy
//  — returning the same `[TeamContentItem]`. The async signature is already shaped
//  for it; the ViewModel/views don't change. A live source would also carry real
//  per-post thumbnails (the seed renders a designed crest tile — see
//  TeamContentCard) and real per-post deep links instead of channel-level URLs.
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

    private static func item(
        _ id: String, _ abbr: String, _ platform: TeamContentItem.Platform,
        _ hours: Double, _ caption: String, _ url: String, duration: String? = nil
    ) -> TeamContentItem {
        TeamContentItem(
            id: id, teamAbbreviation: abbr, platform: platform,
            timestamp: hoursAgo(hours), caption: caption,
            durationLabel: duration, url: URL(string: url)
        )
    }

    // Real, durable official account URLs (verified, 2026 season).
    private static let yt: [String: String] = [
        "LA":  "https://www.youtube.com/@AngelCityFC",
        "BAY": "https://www.youtube.com/@WeAreBayFC",
        "BOS": "https://www.youtube.com/@BostonLegacyFC",
        "CHI": "https://www.youtube.com/chicagoredstarsnwsl",
        "DEN": "https://www.youtube.com/channel/UC55HcqZQqqdnkjsWWrD01Wg",
        "GFC": "https://www.youtube.com/channel/UCX5SydaP78jaqqcNx9ZrrtQ",
        "HOU": "https://www.youtube.com/user/houstondash",
        "KC":  "https://www.youtube.com/kccurrent",
        "NC":  "https://www.youtube.com/c/NorthCarolinaCourage",
        "ORL": "https://www.youtube.com/@ORLPride",
        "POR": "https://www.youtube.com/user/PortlandThornsFC",
        "LOU": "https://www.youtube.com/channel/UC3xOx0RR9rerRp20jJyHQdw",
        "SD":  "https://www.youtube.com/@sandiegowavefc",
        "SEA": "https://www.youtube.com/seattlereignfc",
        "UTA": "https://www.youtube.com/@utahroyalsfc",
        "WAS": "https://www.youtube.com/WashingtonSpirit",
    ]
    private static let ig: [String: String] = [
        "LA":  "https://www.instagram.com/weareangelcity",
        "BAY": "https://www.instagram.com/wearebayfc",
        "BOS": "https://www.instagram.com/bostonlegacyfc",
        "CHI": "https://www.instagram.com/thechicagostars",
        "DEN": "https://www.instagram.com/denversummit_fc",
        "GFC": "https://www.instagram.com/gothamfc",
        "HOU": "https://www.instagram.com/houstondash",
        "KC":  "https://www.instagram.com/kccurrent",
        "NC":  "https://www.instagram.com/thenccourage",
        "ORL": "https://www.instagram.com/orlpride",
        "POR": "https://www.instagram.com/thornsfc",
        "LOU": "https://www.instagram.com/racinglouisvillefc",
        "SD":  "https://www.instagram.com/sandiegowavefc",
        "SEA": "https://www.instagram.com/reignfc",
        "UTA": "https://www.instagram.com/utahroyalsfc",
        "WAS": "https://www.instagram.com/washingtonspirit",
    ]

    private static let seed: [TeamContentItem] = [
        // Angel City FC
        item("LA-1", "LA", .youtube, 5, "Mic'd up: a forward's first goal of the season, told in her own words", yt["LA"]!, duration: "6:18"),
        item("LA-2", "LA", .instagram, 14, "Pregame fits at BMO — rate the looks 🔥", ig["LA"]!),

        // Bay FC
        item("BAY-1", "BAY", .youtube, 8, "Inside training: finishing drills ahead of the road trip", yt["BAY"]!, duration: "4:47"),
        item("BAY-2", "BAY", .instagram, 21, "A look around the Bay before kickoff 🌉", ig["BAY"]!),

        // Boston Legacy FC
        item("BOS-1", "BOS", .instagram, 3, "First home kits have landed. Welcome to the Legacy. 🟢", ig["BOS"]!),
        item("BOS-2", "BOS", .youtube, 18, "Building a club from scratch: meet the inaugural squad", yt["BOS"]!, duration: "8:02"),

        // Chicago Stars FC
        item("CHI-1", "CHI", .youtube, 7, "Locker room reaction after a hard-fought point on the road", yt["CHI"]!, duration: "3:29"),
        item("CHI-2", "CHI", .instagram, 26, "Matchday at Wrigleyville-adjacent ⭐️ tap in", ig["CHI"]!),

        // Denver Summit FC
        item("DEN-1", "DEN", .instagram, 4, "Altitude advantage. First season, new heights. ⛰️", ig["DEN"]!),
        item("DEN-2", "DEN", .youtube, 16, "Expansion diaries: building the Summit from day one", yt["DEN"]!, duration: "7:33"),

        // Gotham FC
        item("GFC-1", "GFC", .youtube, 6, "Behind the scenes: a clean sheet on the road", yt["GFC"]!, duration: "5:11"),
        item("GFC-2", "GFC", .instagram, 19, "Saturday in the city. You coming? 🗽", ig["GFC"]!),

        // Houston Dash
        item("HOU-1", "HOU", .instagram, 9, "Sunset training session at Shell Energy 🧡", ig["HOU"]!),
        item("HOU-2", "HOU", .youtube, 30, "Get to know the new signings — three things you didn't know", yt["HOU"]!, duration: "4:05"),

        // Kansas City Current
        item("KC-1", "KC", .youtube, 5, "CPKC Stadium walkout — the view that never gets old", yt["KC"]!, duration: "2:54"),
        item("KC-2", "KC", .instagram, 23, "Teal takeover. Another sellout on the river. 💙", ig["KC"]!),

        // North Carolina Courage
        item("NC-1", "NC", .youtube, 10, "Tactics cam: breaking down the high press in slow motion", yt["NC"]!, duration: "6:40"),
        item("NC-2", "NC", .instagram, 28, "Cary, we're home this weekend. Bring the noise. 🐾", ig["NC"]!),

        // Orlando Pride
        item("ORL-1", "ORL", .instagram, 6, "Pride night at Inter&Co — the city lit up purple 💜", ig["ORL"]!),
        item("ORL-2", "ORL", .youtube, 22, "Champions mentality: a defender on holding the back line together", yt["ORL"]!, duration: "5:48"),

        // Portland Thorns FC
        item("POR-1", "POR", .youtube, 7, "The Rose City roar — walking out at Providence Park", yt["POR"]!, duration: "3:12"),
        item("POR-2", "POR", .instagram, 25, "Thorns 'til I die. Matchday, Rose City. 🌹", ig["POR"]!),

        // Racing Louisville FC
        item("LOU-1", "LOU", .instagram, 11, "Lynn Family Stadium under the lights ⚡️", ig["LOU"]!),
        item("LOU-2", "LOU", .youtube, 33, "Young core, big dreams: a midfielder on finding her feet", yt["LOU"]!, duration: "4:21"),

        // San Diego Wave FC
        item("SD-1", "SD", .youtube, 4, "Beach day with the squad — recovery, SoCal style 🌊", yt["SD"]!, duration: "5:02"),
        item("SD-2", "SD", .instagram, 20, "Snapdragon sunset. Wave fam, pull up. 💙", ig["SD"]!),

        // Seattle Reign FC
        item("SEA-1", "SEA", .instagram, 8, "Rain or shine, Seattle shows up ☔️ tap in", ig["SEA"]!),
        item("SEA-2", "SEA", .youtube, 27, "Mic'd up at Lumen — keeper edition", yt["SEA"]!, duration: "6:55"),

        // Utah Royals
        item("UTA-1", "UTA", .youtube, 5, "Top of the table: the unbeaten run, told by the players", yt["UTA"]!, duration: "7:09"),
        item("UTA-2", "UTA", .instagram, 24, "America First Field is rocking 👑 matchday in Utah", ig["UTA"]!),

        // Washington Spirit
        item("WAS-1", "WAS", .instagram, 3, "Audi Field is sold out again. Spirit til the end. 🔵", ig["WAS"]!),
        item("WAS-2", "WAS", .youtube, 17, "Get to know the rookie class — rapid-fire Q&A", yt["WAS"]!, duration: "4:38"),
    ]
}
