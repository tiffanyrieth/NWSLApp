//
//  PlayerSpotlight.swift
//  NWSLApp
//
//  One "Player of the week" for Home's Module 2 ("Get to know your players").
//  Per Reference/Design/spotlight-design-spec.md the card is Option B — a mini
//  profile that sells the player before you tap: a bio blurb (the hook) plus a
//  video thumbnail. Tapping pushes a dedicated PlayerSpotlightView (video +
//  extended profile) — deliberately NOT PlayerDetailView (spotlight is narrative,
//  "meet this person"; PlayerDetail is reference, "what are their stats").
//
//  Flat and view-friendly like TeamContentItem/FeedItem: it carries the team's
//  `abbreviation` as the join key (so the ViewModel can rotate per-followed-team
//  and resolve crest/name from the Club directory) plus everything the card and
//  the detail page render. The model is shaped for the future content pipeline
//  (spec §"Content pipeline") — a real source fills the same fields.
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

    /// The 2-3 sentence hook (spec §Home card format): what makes this player
    /// worth caring about, shown right on the Home card so the content sells
    /// itself on the scroll. Also leads the detail page.
    let bioBlurb: String

    // MARK: Video (the "watch" content)
    //
    // A real, verified player-focused video (a "get to know"/feature/mic'd-up/
    // interview). `videoURL` is nil for a written-only profile — the spec's
    // explicit fallback for players without good video (e.g. content that lives
    // only on Facebook). When nil the card hides the thumbnail and the detail
    // page is bio-only.

    let videoURL: URL?
    /// The YouTube video id backing `videoURL` — drives `thumbnailURL`. Nil for a
    /// written-only profile (no video). The seed's videos are all YouTube, so this
    /// is set whenever `videoURL` is; a non-YouTube source would leave it nil and
    /// the card/hero falls back to the designed crest tile.
    let youTubeVideoID: String?
    /// Real video title, e.g. "Mic'd Up with Messiah Bright".
    let videoTitle: String?
    /// Where the video lives, for honest attribution ("Houston Dash",
    /// "The Women's Game", "Victory+") — shown as "via …".
    let videoSource: String?
    // NOTE: no duration field — the spotlight card/hero doesn't show a runtime
    // badge (unlike Module 1's TeamContentCard), so the seed doesn't carry one.

    /// Public 16:9 thumbnail for the card and the detail hero, built from the
    /// YouTube video id. `hqdefault.jpg` is the durable frame YouTube serves for a
    /// valid id. Nil for written-only profiles (then: the designed crest tile).
    var thumbnailURL: URL? {
        guard let id = youTubeVideoID else { return nil }
        return URL(string: "https://img.youtube.com/vi/\(id)/hqdefault.jpg")
    }

    // MARK: Extended profile (spec §Tap-through — the detail page)

    let nationality: String?
    /// A 2026 snapshot (age rots yearly — acceptable for the TEMP seed; a real
    /// source would carry a birth date and compute it). Nil when genuinely
    /// uncertain, so the detail page omits it rather than asserting a guess.
    let age: Int?
    let careerHighlights: [String]
    let funFacts: [String]
    /// Current-season form ("4 goals, 2 assists") — optional and volatile, so
    /// nil in the seed today; a live stats source fills it (spec §Tap-through).
    let seasonForm: String?
}
