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

    var body: some View {
        switch card.layout {
        case .youtube, .socialVideo:
            ThumbnailContentCard(card: card, club: club)
        case .blueskyTeamText, .blueskyTeamMedia, .blueskyReporter, .instagramFallback:
            AvatarContentCard(card: card, club: club)
        case .newsArticle:
            ArticleContentCard(card: card, club: club)
        }
    }
}
