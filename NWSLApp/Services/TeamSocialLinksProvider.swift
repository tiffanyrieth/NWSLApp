//
//  TeamSocialLinksProvider.swift
//  NWSLApp
//
//  ⚠️ TEMP / SCAFFOLDING — curated static seed for the TeamDetailView header's
//  social-links row.
//
//  WHAT: each club's official social / community accounts (Reddit, Bluesky,
//  Instagram, YouTube, TikTok), keyed by team abbreviation, in display order. Only
//  the platforms a club actually uses are listed — a club with no subreddit simply
//  has no Reddit icon (the spec forbids dead icons). YouTube + Instagram are the
//  same verified account URLs TeamContentProvider uses; Reddit/Bluesky/TikTok were
//  web-verified for the 2026 season.
//
//  WHY: there's no backend yet, so this lets the row be fully functional. The async
//  `links(for:)` signature is already shaped for a real source (a club-profile
//  endpoint or the planned proxy) — swap the body and neither the view model nor
//  the views change.
//
//  VERIFY-BEFORE-SHIP caveats (Reddit is the soft spot — the firehose is
//  unfetchable here, so subreddits were confirmed indirectly):
//   • KC  — r/KCCurrent is the conventional handle but the lowest-confidence cell;
//           re-check (or drop to none) before a real ship.
//   • CHI — r/redstars kept over r/ChicagoStars: fan subs rarely migrate on the
//           Red Stars → Chicago Stars rebrand, but the newer sub may overtake it.
//   • BOS, DEN, LOU — no subreddit (BOS/DEN are 2026 expansion sides); omitted, not
//           guessed. Their Bluesky/TikTok come from each club's official site.
//
//  WHEN REMOVED: replace `links(for:)` with the real source returning the same
//  TeamSocialLinks. The YT/IG overlap with TeamContentProvider collapses then too
//  (one club-links source of truth instead of two curated seeds).
//

import Foundation

struct TeamSocialLinksProvider {
    /// The curated links for a club, or nil if the abbreviation isn't seeded. Async
    /// to mirror the eventual networked source, though today it resolves immediately.
    func links(for abbreviation: String) async -> TeamSocialLinks? {
        Self.seed[abbreviation]
    }

    /// Assembles a club's links in `SocialPlatform` display order, dropping any
    /// platform the club doesn't have (nil URL) so the row shows no dead icons.
    private static func make(_ abbr: String) -> TeamSocialLinks {
        let ordered: [(SocialPlatform, String?)] = [
            (.reddit, reddit[abbr]),
            (.bluesky, bluesky[abbr]),
            (.instagram, instagram[abbr]),
            (.youtube, youtube[abbr]),
            (.tiktok, tiktok[abbr]),
        ]
        let links = ordered.compactMap { platform, urlString -> SocialLink? in
            guard let urlString, let url = URL(string: urlString) else { return nil }
            return SocialLink(platform: platform, url: url)
        }
        return TeamSocialLinks(teamAbbreviation: abbr, links: links)
    }

    private static let abbreviations = [
        "LA", "BAY", "BOS", "CHI", "DEN", "GFC", "HOU", "KC",
        "NC", "ORL", "POR", "LOU", "SD", "SEA", "UTA", "WAS",
    ]

    private static let seed: [String: TeamSocialLinks] = Dictionary(
        uniqueKeysWithValues: abbreviations.map { ($0, make($0)) }
    )

    // MARK: - Per-platform account URLs (real, verified — 2026 season)

    // YouTube + Instagram: the same official URLs as TeamContentProvider (TEMP
    // overlap — both seeds collapse into one real source later).
    private static let youtube: [String: String] = [
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
    private static let instagram: [String: String] = [
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

    // Reddit: a club's primary community subreddit. BOS/DEN/LOU intentionally absent
    // (no subreddit — see header caveats); KC/CHI are the soft cells.
    private static let reddit: [String: String] = [
        "LA":  "https://www.reddit.com/r/angelcityfc",
        "BAY": "https://www.reddit.com/r/BayFC",
        "CHI": "https://www.reddit.com/r/redstars",
        "GFC": "https://www.reddit.com/r/gothamfc",
        "HOU": "https://www.reddit.com/r/Dash",
        "KC":  "https://www.reddit.com/r/KCCurrent",
        "NC":  "https://www.reddit.com/r/nccourage",
        "ORL": "https://www.reddit.com/r/orlandopride",
        "POR": "https://www.reddit.com/r/thorns",
        "SD":  "https://www.reddit.com/r/sandiegowave",
        "SEA": "https://www.reddit.com/r/reignfc",
        "UTA": "https://www.reddit.com/r/utahroyalsfc",
        "WAS": "https://www.reddit.com/r/washingtonspirit",
    ]

    // Bluesky: GFC/KC/DEN use *.bsky.social handles; the rest use custom domains.
    private static let bluesky: [String: String] = [
        "LA":  "https://bsky.app/profile/angelcity.com",
        "BAY": "https://bsky.app/profile/bayfc.com",
        "BOS": "https://bsky.app/profile/bostonlegacyfc.com",
        "CHI": "https://bsky.app/profile/chicagostars.com",
        "DEN": "https://bsky.app/profile/denversummitfc.bsky.social",
        "GFC": "https://bsky.app/profile/gothamfc.bsky.social",
        "HOU": "https://bsky.app/profile/houstondash.com",
        "KC":  "https://bsky.app/profile/kansascitycurrent.bsky.social",
        "NC":  "https://bsky.app/profile/nccourage.com",
        "ORL": "https://bsky.app/profile/orlpride.com",
        "POR": "https://bsky.app/profile/thornsfc.com",
        "LOU": "https://bsky.app/profile/racingloufc.com",
        "SD":  "https://bsky.app/profile/sandiegowavefc.com",
        "SEA": "https://bsky.app/profile/reignfc.com",
        "UTA": "https://bsky.app/profile/utahroyalsfc.com",
        "WAS": "https://bsky.app/profile/washingtonspirit.com",
    ]

    // TikTok: note the non-obvious handles (LA/BAY/UTA, and HOU has a dot).
    private static let tiktok: [String: String] = [
        "LA":  "https://www.tiktok.com/@weareangelcity",
        "BAY": "https://www.tiktok.com/@wearebayfc",
        "BOS": "https://www.tiktok.com/@bostonlegacyfc",
        "CHI": "https://www.tiktok.com/@thechicagostars",
        "DEN": "https://www.tiktok.com/@denversummitfc",
        "GFC": "https://www.tiktok.com/@gothamfc",
        "HOU": "https://www.tiktok.com/@houston.dash",
        "KC":  "https://www.tiktok.com/@thekccurrent",
        "NC":  "https://www.tiktok.com/@thenccourage",
        "ORL": "https://www.tiktok.com/@orlandopride",
        "POR": "https://www.tiktok.com/@thornsfc",
        "LOU": "https://www.tiktok.com/@racingloufc",
        "SD":  "https://www.tiktok.com/@sandiegowavefc",
        "SEA": "https://www.tiktok.com/@reignfc",
        "UTA": "https://www.tiktok.com/@utahroyalsofficial",
        "WAS": "https://www.tiktok.com/@washspirit",
    ]
}
