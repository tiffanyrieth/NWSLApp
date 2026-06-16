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
    /// When the user follows exactly one team, team identification on the card is
    /// redundant noise — Home passes `true` to drop the team badge + name (keeping the
    /// platform badge + accent line). Feed never sets it.
    var hideTeamIdentity: Bool = false

    var body: some View {
        // The facelift "color-block" signature: a 3px team-color bar down the card's
        // left edge (home.jsx). Applied once here so all three layouts get it
        // uniformly; re-clipped to the card's rounded rect so the bar follows the
        // corners. A team-less card (reporter/league) gets no bar (no blue fallback).
        layoutCard
            .overlay(alignment: .leading) {
                if let color = club?.accentColor {
                    Rectangle().fill(color).frame(width: 3)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous))
    }

    @ViewBuilder
    private var layoutCard: some View {
        switch card.layout {
        case .youtube, .socialVideo:
            ThumbnailContentCard(card: card, club: club, hideTeamIdentity: hideTeamIdentity)
        case .blueskyTeamText, .blueskyTeamMedia, .blueskyReporter, .instagramFallback:
            AvatarContentCard(card: card, club: club, hideTeamIdentity: hideTeamIdentity)
        case .newsArticle:
            ArticleContentCard(card: card, club: club, hideTeamIdentity: hideTeamIdentity)
        }
    }
}
