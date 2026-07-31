//
//  ContentCardView.swift
//  NWSLApp
//
//  The single entry point for rendering any ContentCard. Home and Feed call only
//  this — it switches on `card.layout` and routes to one of the three card views
//  (thumbnail-forward, avatar-led, or article). Keeping the routing in one place
//  means the screens stay agnostic about which of the seven variants they're
//  showing; they just hand over a card (and, when known, the matching Club for the
//  crest + team color).
//

import SwiftUI

struct ContentCardView: View {
    let card: ContentCard
    /// The followed club this card is about, resolved by abbreviation. Optional —
    /// reporter/league/creator cards have no team, and the views degrade to the
    /// app accent.
    var club: Club?
    /// When the user follows exactly one team, team identification on the card is redundant
    /// noise — every card would be the same club. Home/Feed pass `true` to drop the team badge,
    /// the team name, AND (since 2026-07-31) the left-edge team color bar. The platform badge
    /// stays: "which club" is redundant at one team, "Instagram vs YouTube vs article" is not.
    var hideTeamIdentity: Bool = false
    /// Social tab passes `true` for the unified card chrome (category pills, no avatar).
    /// Home leaves it `false` to keep its original card chrome — the team label is the
    /// only thing that changed on Home (now a bottom-left on-media chip).
    var unified: Bool = false

    /// THE one definition of "the user follows too few teams for per-card team identity to mean
    /// anything". Home, the Home content list and Feed all gate on this — spelled out separately in
    /// each, they drift (the Bracket rank line had exactly that happen across four call sites, with
    /// two different thresholds and two rounding rules producing different numbers on different
    /// screens). Change the rule here and every surface follows.
    static func hidesTeamIdentity(followedTeamCount: Int) -> Bool { followedTeamCount <= 1 }

    /// The 3px team-color bar down the card's left edge — shown ONLY when the user follows 2+
    /// teams. It exists to let you tell whose card is whose while scrolling (purple = Pride,
    /// yellow = Utah) without reading a word. Following ONE team, every card would carry the
    /// same color: a visual distinction implying a difference that isn't there.
    ///
    /// This is the same rule that already hides the team chip + name at one team
    /// (`hideTeamIdentity`); the bar used to be carved out of it and no longer is (owner,
    /// 2026-07-31). Nice side effect: following a second club INTRODUCES the color coding at
    /// exactly the moment it starts carrying information.
    private var showsTeamBar: Bool { !hideTeamIdentity }

    var body: some View {
        // Applied once here so all three layouts get it uniformly; re-clipped to the card's
        // rounded rect so the bar follows the corners. A team-less card (reporter/league) gets
        // no bar either (no blue fallback).
        layoutCard
            .overlay(alignment: .leading) {
                if showsTeamBar, let color = club?.accentColor {
                    Rectangle().fill(color).frame(width: 3)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous))
    }

    @ViewBuilder
    private var layoutCard: some View {
        switch card.layout {
        case .youtube, .socialVideo:
            ThumbnailContentCard(card: card, club: club, hideTeamIdentity: hideTeamIdentity, unified: unified)
        case .blueskyTeamText, .blueskyTeamMedia, .blueskyReporter, .instagramFallback:
            // Avatar (Bluesky) cards are Social-only — always the unified chrome.
            AvatarContentCard(card: card, club: club, hideTeamIdentity: hideTeamIdentity)
        case .newsArticle:
            ArticleContentCard(card: card, club: club, hideTeamIdentity: hideTeamIdentity, unified: unified)
        }
    }
}
