//
//  TeamAbbrPill.swift
//  NWSLApp
//
//  The small club-abbreviation chip (e.g. "LA", "WAS") drawn in the club's color on
//  content cards — the "which club" marker (distinct from CategoryPill's "what kind of
//  voice" marker). Was hand-coded identically in AvatarContentCard + ArticleContentCard;
//  this is the single shared version.
//

import SwiftUI

struct TeamAbbrPill: View {
    let abbr: String
    let color: Color

    var body: some View {
        Text(abbr)
            .dsFont(10.5, weight: .bold)
            .tracking(0.3)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.13), in: Capsule())
    }
}
