//
//  PlayerSpotlight.swift
//  NWSLApp
//
//  One "Player of the week" for Home's Module 2 ("Get to know your players").
//  The spec made this module visible by default — a compact card that introduces
//  the roster one person at a time and differentiates the app (learn the players,
//  not homework). See Reference/Design/home-tab-design-spec.md.
//
//  Flat and view-friendly like TeamContentItem/FeedItem: it carries the team's
//  `abbreviation` as the join key (so the ViewModel can rotate through the user's
//  followed teams and resolve crest/color from the Club directory) plus the few
//  fields the card shows. The full rotation mechanics + a real content pipeline
//  are a future design session (spec: "Full mechanics TBD"); today a curated seed
//  (PlayerSpotlightProvider) backs it.
//

import Foundation

struct PlayerSpotlight: Identifiable {
    let id: String

    /// The followed-team join key (matched to a Club by abbreviation).
    let teamAbbreviation: String

    let playerName: String
    /// Shirt number shown in the team-color jersey badge.
    let jerseyNumber: Int
    /// "Forward" / "Midfielder" / "Defender" / "Goalkeeper".
    let position: String

    /// The "Watch spotlight" link — a real team channel where the player's content
    /// lives (a per-player deep link arrives with a real content source).
    let watchURL: URL?
}
