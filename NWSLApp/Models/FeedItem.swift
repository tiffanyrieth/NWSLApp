//
//  FeedItem.swift
//  NWSLApp
//
//  One item in the Feed tab — "the world talking about your teams" (reporters,
//  news outlets), as opposed to Home Module 2 which is "the teams talking to
//  you" (see Reference/Design/feed-tab-design-spec.md).
//
//  Two content shapes share one model so they can be mixed chronologically:
//   • .reporterPost — a Bluesky/Twitter post (full body text + a "View on …" link)
//   • .articleLink  — a news article (bold headline + 1-line summary + a "Read
//                     on …" link). Legal line from the spec: headline + summary
//                     + link only, NEVER the article body.
//
//  The model is intentionally flat and view-friendly (and Codable-shaped) so the
//  current TEMP static seed (FeedContentProvider) can later be swapped for a real
//  backend — a Bluesky/news aggregator or the planned caching proxy — with no
//  change to the ViewModel or views.
//

import Foundation

/// A team an item is tagged to, identified by abbreviation so the Feed's filters
/// can match items to the user's followed clubs (by abbreviation, mirroring how
/// MatchStore joins clubs to games — ESPN gives us no stable competitor id).
/// It carries only the join key: the team isn't shown on the card (the top
/// filter bar is the team selector), and any display name/color is available
/// from the club directory if ever needed.
struct FeedTeamTag: Identifiable, Hashable {
    let abbreviation: String   // "WAS", "LA" — matches Club.abbreviation
    var id: String { abbreviation }
}

struct FeedItem: Identifiable {
    enum Kind {
        case reporterPost   // Bluesky / Twitter
        case articleLink    // The Athletic / ESPN / etc.
    }

    let id: String
    let kind: Kind

    /// Reporter name ("Meg Linehan") or publication ("The Athletic").
    let sourceName: String
    /// Reporter handle ("@meglinehan") — reporter posts only; nil for articles.
    let sourceHandle: String?
    /// Where it came from, shown next to the timestamp: "Bluesky", "Twitter",
    /// "The Athletic", "ESPN".
    let platform: String
    let timestamp: Date

    /// Article headline (bold) — `.articleLink` only.
    let headline: String?
    /// One-line article summary — `.articleLink` only.
    let summary: String?
    /// Full post text — `.reporterPost` only.
    let body: String?

    /// External link opened by the card's "View on …" / "Read on …" action.
    let url: URL?

    /// Teams this item is about — the join key for the per-team filters (an item
    /// surfaces under each of its teams' chips). Empty when `isLeague` is true
    /// (league-wide content isn't tied to a club). Two+ tags = multi-team content.
    let teams: [FeedTeamTag]

    /// League-wide news (power rankings, expansion, rule changes) — surfaced
    /// under the dedicated "League" chip rather than any one team.
    let isLeague: Bool

    /// The action-link label per content type, e.g. "View on Bluesky" /
    /// "Read on The Athletic".
    var linkLabel: String {
        switch kind {
        case .reporterPost: return "View on \(platform)"
        case .articleLink:  return "Read on \(platform)"
        }
    }
}
