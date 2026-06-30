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

/// A platform shown in the team social row, in display order. Each maps to a
/// bundled brand glyph in the asset catalog's `Social/` namespace (template
/// images, tinted at the call site). The content cards (`TeamContentItem.Platform`)
/// still use SF Symbols — the social row is the surface that earns real logos.
enum SocialPlatform: String, CaseIterable {
    case reddit = "Reddit"
    case bluesky = "Bluesky"
    case instagram = "Instagram"
    case youtube = "YouTube"
    case tiktok = "TikTok"

    /// Human-facing label shown under the icon (the platform name, not the handle
    /// — cleaner at small sizes, per the spec).
    var label: String { rawValue }

    /// Asset-catalog name of the platform's brand glyph — a template image under
    /// the `Social/` namespace (`Social/bluesky`, etc.), tinted at the call site
    /// via `.foregroundStyle`. Bundled vector (SVG), so it renders on the first
    /// frame with no network.
    var iconAssetName: String {
        switch self {
        case .reddit:    return "Social/reddit"
        case .bluesky:   return "Social/bluesky"
        case .instagram: return "Social/instagram"
        case .youtube:   return "Social/youtube"
        case .tiktok:    return "Social/tiktok"
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
