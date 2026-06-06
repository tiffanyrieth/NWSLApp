//
//  TeamSocialLinks.swift
//  NWSLApp
//
//  A club's social / community links, surfaced as a row of circular icon buttons
//  in the TeamDetailView header (between the standing line and the Squad/Stats
//  sub-tabs) per Reference/Design/teams-tab-design-spec.md. The links are part of
//  the team's identity — connecting fans to the club's official accounts and
//  community spaces — and are deliberately distinct from the Feed tab (reporters /
//  news ABOUT the team) and Home Module 1 (the team's own content posts).
//
//  Like the rest of the app, a club is joined by its `abbreviation` (ESPN gives no
//  stable competitor id), and the curated link set lives behind an async provider
//  (TeamSocialLinksProvider) so it can be swapped for a real source later with no
//  change to the view model or views.
//

import Foundation

/// A platform shown in the team social row, in display order. Each maps to an SF
/// Symbol glyph — SF Symbols ships no third-party brand logos, so these are
/// approximations, the same convention `TeamContentItem.Platform` uses for the
/// content cards (the four shared cases use the same symbols on purpose).
enum SocialPlatform: String, CaseIterable {
    case reddit = "Reddit"
    case bluesky = "Bluesky"
    case instagram = "Instagram"
    case youtube = "YouTube"
    case tiktok = "TikTok"

    /// Human-facing label shown under the icon (the platform name, not the handle
    /// — cleaner at small sizes, per the spec).
    var label: String { rawValue }

    /// SF Symbol glyph for the icon. The four platforms shared with
    /// `TeamContentItem.Platform` reuse its symbols for a consistent look; Reddit
    /// (community discussion) gets the double-bubble to read distinctly from
    /// Bluesky's single bubble.
    var symbol: String {
        switch self {
        case .reddit:    return "bubble.left.and.bubble.right.fill"
        case .bluesky:   return "bubble.left.fill"
        case .instagram: return "camera.fill"
        case .youtube:   return "play.rectangle.fill"
        case .tiktok:    return "music.note"
        }
    }
}

/// One social account: a platform + the URL its icon opens.
struct SocialLink: Identifiable {
    let platform: SocialPlatform
    let url: URL

    /// Stable within a club's row — a club has at most one link per platform.
    var id: SocialPlatform { platform }
}

/// A club's social links, keyed by team abbreviation. Only platforms the club
/// actually uses are present, so the row renders exactly what's here — no dead
/// icons for platforms a team doesn't have (a spec requirement).
struct TeamSocialLinks {
    let teamAbbreviation: String
    /// In `SocialPlatform` declaration order (Reddit → Bluesky → IG → YT → TikTok).
    let links: [SocialLink]
}
