//
//  ContentCard.swift
//  NWSLApp
//
//  One piece of ALIVE content — a YouTube video, a Bluesky post, a news article,
//  a TikTok/IG clip surfaced via Reddit — rendered as a card on Home ("From your
//  teams") or in the Feed tab. This single flat model supersedes the two earlier,
//  narrower ones (TeamContentItem for Home, FeedItem for Feed): both screens now
//  speak one vocabulary, so a card can be authored once and placed by rule.
//
//  Design source: the Claude Design "Content Card Spec" (7 pixel-perfect
//  variants); see Reference/nwslapp-design-system/project/Content Card Spec.html.
//  Each `Layout` is one of those variants; `ContentCardView` routes a card to the
//  right view.
//
//  The model is deliberately flat and fully `Codable` so it decodes straight from
//  the live proxy routes that return `[ContentCard]` JSON (YouTube Data API,
//  Bluesky AT Protocol, Reddit, news RSS, all fetched + normalized in the
//  nwslapp-proxy Worker). (Fixture cards for previews/tests share the same shape.)
//  Per-layout line-clamps,
//  paddings, and overlays live in the VIEW, not here; this carries only data.
//

import Foundation

struct ContentCard: Identifiable, Codable, Hashable {

    /// The visual variant — picks the card view and its layout rules.
    enum Layout: String, Codable {
        case youtube            // 1. YouTube video — thumbnail-forward (Home)
        case blueskyTeamText    // 2. Team Bluesky post, text only (Home)
        case blueskyTeamMedia   // 3. Team Bluesky post, with media (Home)
        case blueskyReporter    // 4. Reporter Bluesky post (Feed)
        case newsArticle        // 5. News article via RSS (Feed)
        case socialVideo        // 6. TikTok/IG clip via Reddit (Feed + Home)
        case instagramFallback  // 7. IG post with no thumbnail — fallback strip
    }

    /// The originating platform — drives the `PlatformBadge` color + glyph.
    enum Platform: String, Codable {
        case youtube, bluesky, tiktok, instagram, article, reddit
    }

    /// Where a card is allowed to appear, enforced by the placement gate in the
    /// view models (Home = official team voices only; Feed = the wider
    /// conversation). `.both` rides a team-tagged social clip onto either.
    enum Placement: String, Codable {
        case home, feed, both
    }

    /// The source class behind a card, set by the proxy — drives the Feed's chip bar
    /// (Clubs · Reporters · Players · News). `league` = NWSL media/league-outlet
    /// social accounts (grouped under the Reporters chip). Optional: seed/older cards
    /// and player cards from an older cron snapshot lack it, so the Feed infers it
    /// from `layout` as a fallback (see FeedViewModel.sourceType(of:)).
    enum SourceType: String, Codable {
        case club, reporter, player, league, news
    }

    let id: String
    let layout: Layout
    let platform: Platform
    let placement: Placement
    /// Source class for the Feed chips; nil on seed/older cards (inferred from layout).
    var sourceType: SourceType? = nil

    /// Join key → the followed `Club`'s crest + color (matched by abbreviation,
    /// the same join MatchStore/Home use; ESPN has no stable competitor id). Nil
    /// for reporter posts and league-wide content.
    let teamAbbreviation: String?
    /// League-wide content (power rankings, the break, rule changes) — surfaced in
    /// the Feed regardless of which clubs are followed.
    let isLeague: Bool

    /// Display name on the card: a team ("Washington Spirit"), a reporter
    /// ("Meg Linehan"), a creator ("@trinity_rodman"), or an outlet ("ESPN").
    let authorName: String?
    /// Social handle ("@meglinehan") — Bluesky layouts.
    let handle: String?
    /// Subreddit a social clip was surfaced through ("NWSL") — layout 6's "via r/…".
    let subreddit: String?
    /// Outlet name for articles ("The Athletic") — also a mute key; see `muteKey`.
    let sourceName: String?

    /// YouTube title / social-clip caption headline.
    let title: String?
    /// Article headline (bold) — layout 5.
    let headline: String?
    /// Article one-line summary — layout 5.
    let blurb: String?
    /// Post body / clip caption — Bluesky + social layouts.
    let bodyText: String?

    /// The card's image: a YouTube frame, Bluesky media, a clip frame, or an
    /// article thumb. Nil falls back to a team-crest/gradient tile (never a broken
    /// image). For YouTube, build from the video id: `youTubeThumbnail(_:)`.
    let thumbnailURL: URL?
    /// Video length label ("4:12") for the thumbnail's duration pill.
    let duration: String?
    /// Marks the IG-fallback layout (no usable thumbnail → the fallback strip).
    let igFallback: Bool

    let likes: Int?
    let reposts: Int?

    /// Sort key (newest-first within a club's slots) and the "2h ago" label. NOT a
    /// freshness gate — representation is count-based and age-agnostic (see
    /// ContentRoundRobin): a club's most-recent posts always surface regardless of age.
    let timestamp: Date
    /// External tap target — opens the native app / Safari. Whole card is the link.
    let url: URL?
    /// The action-link text: "View on Bluesky", "Read article", "Open in TikTok".
    let ctaLabel: String

    /// The key the Feed's per-source mute list matches on: the outlet for articles,
    /// else the author (reporter/creator/team).
    var muteKey: String { sourceName ?? authorName ?? "" }

    /// The public 480×360 thumbnail YouTube always serves for a valid video id.
    static func youTubeThumbnail(_ videoID: String) -> URL? {
        URL(string: "https://img.youtube.com/vi/\(videoID)/hqdefault.jpg")
    }
}
