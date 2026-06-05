//
//  TeamContentItem.swift
//  NWSLApp
//
//  One item in Home's Module 1 ("From your teams") — the teams' OWN voices:
//  official YouTube videos, Instagram posts, TikToks, team Bluesky. This is the
//  hook the spec leads Home with (Reference/Design/home-tab-design-spec.md), and
//  it's deliberately distinct from the Feed tab, which is the wider ecosystem
//  (reporters, news) talking ABOUT your teams. Home Module 1 = the teams talking
//  TO you.
//
//  The model is flat and view-friendly (Codable-shaped) so the current TEMP
//  static seed (TeamContentProvider) can later be swapped for a real source — a
//  team-channel aggregator or the planned caching proxy — with no change to the
//  ViewModel or views. It mirrors FeedItem's design: the item carries only the
//  team's `abbreviation` as the join key; the crest + team name shown in the
//  card's attribution line are resolved from the followed Club (by abbreviation,
//  the same join MatchStore/Feed use — ESPN gives no stable competitor id).
//

import Foundation

struct TeamContentItem: Identifiable {
    /// Where the content lives, shown as the "via …" source tag + the thumbnail's
    /// corner glyph. Raw value is the human-facing platform name.
    enum Platform: String {
        case youtube = "YouTube"
        case instagram = "Instagram"
        case tiktok = "TikTok"
        case bluesky = "Bluesky"

        /// SF Symbol marking the platform on the thumbnail corner.
        var symbol: String {
            switch self {
            case .youtube:   return "play.rectangle.fill"
            case .instagram: return "camera.fill"
            case .tiktok:    return "music.note"
            case .bluesky:   return "bubble.left.fill"
            }
        }

        /// True for video platforms — the thumbnail shows a play badge (and a
        /// duration label when present).
        var isVideo: Bool {
            switch self {
            case .youtube, .tiktok: return true
            case .instagram, .bluesky: return false
            }
        }
    }

    let id: String

    /// The team whose channel this came from — the join key for the per-team
    /// resolution against the followed clubs (matched by abbreviation). The crest
    /// and name aren't stored here; they're looked up from the Club directory.
    let teamAbbreviation: String

    let platform: Platform
    let timestamp: Date

    /// The post title / caption shown under the thumbnail.
    let caption: String

    /// Video length label ("4:12") for the thumbnail's duration badge — video
    /// platforms only; nil for photo/text posts.
    let durationLabel: String?

    /// External link opened when the card is tapped (the team's channel/profile).
    let url: URL?

    /// "via YouTube" / "via Instagram" — the source tag on the card.
    var sourceTag: String { "via \(platform.rawValue)" }
}
