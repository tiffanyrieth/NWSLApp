//
//  FeedPersonalization.swift
//  NWSLApp
//
//  Phase 3 "make it yours": the decode types for the two proxy routes that back the
//  Content Preferences additions — the featured-player directory (`/feed/players`) and
//  the Bluesky-handle validation (`/feed/validate-reporter`). Both are thin: the proxy
//  owns the curation + relevance check; the app just decodes.
//

import Foundation

/// One featured player from the proxy `/feed/players` directory. `id` is the IG handle —
/// the stable key the app sends back on `/feed`'s `players=` param and matches against a
/// player card's `@<ig>` handle to resolve follows.
struct FeedPlayer: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let team: String
}

/// The proxy `/feed/validate-reporter` result. `found` = the Bluesky account resolves;
/// `hasNWSLPosts` = it has NWSL-relevant posts recently (the app only lets the user ADD a
/// handle that clears both — an existing account with no NWSL content isn't a reporter add).
struct ReporterValidation: Codable {
    let found: Bool
    let displayName: String?
    let handle: String?
    let hasNWSLPosts: Bool?
}
