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

/// A platform shown in the team links row, in display order. Social platforms map
/// to a bundled brand glyph in the asset catalog's `Social/` namespace (template
/// images, tinted at the call site) — the row is the surface that earns real logos.
/// The club's own Website has no brand mark, so it uses a neutral SF Symbol instead
/// (see `glyph`).
enum SocialPlatform: String, CaseIterable {
    // The club's own site (no brand mark of its own) — rendered first in the OFFICIAL
    // row; it links out to the club's shop + tickets, so those don't need their own chips.
    case website = "Website"
    // Third-party social platforms — each with a real brand logo + brand color.
    case reddit = "Reddit"
    case bluesky = "Bluesky"
    case instagram = "Instagram"
    case youtube = "YouTube"
    case tiktok = "TikTok"

    /// Human-facing label shown under the icon (the platform name, not the handle
    /// — cleaner at small sizes, per the spec).
    var label: String { rawValue }

    /// How this platform's glyph is drawn. Social platforms earn their real brand
    /// logo (a bundled template SVG under `Social/`, tinted at the call site);
    /// Website/Shop/Tickets have no brand mark, so they use a neutral SF Symbol.
    enum Glyph {
        case asset(String)   // bundled brand SVG under `Social/`, template-rendered
        case symbol(String)  // SF Symbol name
    }

    var glyph: Glyph {
        switch self {
        case .website:   return .symbol("globe")
        case .reddit:    return .asset("Social/reddit")
        case .bluesky:   return .asset("Social/bluesky")
        case .instagram: return .asset("Social/instagram")
        case .youtube:   return .asset("Social/youtube")
        case .tiktok:    return .asset("Social/tiktok")
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
