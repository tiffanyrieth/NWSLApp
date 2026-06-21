//
//  CategoryPill.swift
//  NWSLApp
//
//  The single "what kind of voice" label on a content card (Social + Home), mapping a
//  card's `resolvedSourceType` to a colored pill — NEWS / LEAGUE / REPORTER / PLAYER /
//  CLUB. It replaces the old source-initials avatar (TE/WS/AC) so a card has exactly
//  ONE labeling system: the club-color bar + club code say WHICH club, this pill says
//  what KIND of voice. Colors come straight from the Feed design mock (`Feed.html`).
//
//  Pills map 1:1 to the Social filter chips, except LEAGUE rides the Headlines chip
//  alongside NEWS (both are "the league's own coverage"): NEWS is a Google-News article
//  ("Read on {outlet}"), LEAGUE is an @NWSL Bluesky post ("View on Bluesky"), and the
//  pill is how the two read apart inside the one filter.
//

import SwiftUI

struct CategoryPill: View {
    let sourceType: ContentCard.SourceType

    var body: some View {
        Text(label)
            .dsFont(9.5, weight: .bold)
            .tracking(0.4)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.16), in: Capsule())
            .fixedSize()   // never compress/clip the pill in the meta row
    }

    private var label: String {
        switch sourceType {
        case .news:     return "NEWS"
        case .league:   return "LEAGUE"
        case .reporter: return "REPORTER"
        case .player:   return "PLAYER"
        case .club:     return "CLUB"
        }
    }

    private var color: Color {
        switch sourceType {
        case .news:     return Color(hex: "#30D158")   // green
        case .league:   return Color(hex: "#32ADE6")   // cyan
        case .reporter: return Color(hex: "#0A84FF")   // blue
        case .player:   return Color(hex: "#FF9F0A")   // orange
        case .club:     return Color(hex: "#BF5AF2")   // purple
        }
    }
}

#Preview {
    HStack(spacing: 7) {
        CategoryPill(sourceType: .news)
        CategoryPill(sourceType: .league)
        CategoryPill(sourceType: .reporter)
        CategoryPill(sourceType: .player)
        CategoryPill(sourceType: .club)
    }
    .padding()
    .background(Color.dsBgGrouped)
}
