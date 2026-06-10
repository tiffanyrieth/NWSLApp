//
//  DSMetrics.swift
//  NWSLApp
//
//  Design-token spacing, corner radii, and fixed sizes — mirrors the design
//  system's `tokens/spacing.css`. One namespace (`DS`) so callsites read
//  `DS.radiusXl`, `DS.pagePadding`, etc. The app uses NO shadows (pure dark
//  flat design), so there are no shadow tokens.
//

import CoreGraphics

/// Design-system metrics (spacing scale, radii, sizes). Values are points.
enum DS {

    // MARK: Spacing scale (named by px value, per tokens/spacing.css)
    static let space2: CGFloat = 4
    static let space3: CGFloat = 6
    static let space4: CGFloat = 8
    static let space5: CGFloat = 10
    static let space6: CGFloat = 12
    static let space7: CGFloat = 14
    static let space8: CGFloat = 16
    static let space9: CGFloat = 18
    static let space10: CGFloat = 20
    static let space11: CGFloat = 24
    static let space12: CGFloat = 28
    static let space13: CGFloat = 32
    static let space14: CGFloat = 40

    // MARK: Semantic spacing
    /// Horizontal page margin (`contentMargins(.horizontal, 16)`).
    static let pagePadding: CGFloat = 16
    /// Vertical gap between Home modules / major sections.
    static let sectionGap: CGFloat = 28
    /// Gap between cards in a list.
    static let cardGap: CGFloat = 12
    /// MatchCard internal padding (h == v here at 16).
    static let cardPadding: CGFloat = 16
    static let chipPaddingH: CGFloat = 14
    static let chipPaddingV: CGFloat = 8

    // MARK: Corner radii
    static let radiusXs: CGFloat = 5     // form badges (W/D/L)
    static let radiusSm: CGFloat = 10    // buttons, stat strips
    static let radiusMd: CGFloat = 12    // ComingUpRow, stat cards, grouped rows
    static let radiusLg: CGFloat = 14    // info cards
    static let radiusXl: CGFloat = 16    // MatchCard, FeedCard, main cards
    static let radiusXxl: CGFloat = 18   // score card, large panels

    // MARK: Avatar / crest sizes
    static let avatarSm: CGFloat = 24    // standings crest
    static let avatarMd: CGFloat = 28    // teams list / coming-up crest
    static let avatarLg: CGFloat = 30    // MatchCard crest
    static let avatarTeams: CGFloat = 32 // teams directory crest
    static let avatarXl: CGFloat = 56    // TeamDetail header crest
    static let avatarMatchHeader: CGFloat = 60 // MatchDetail header crest
    static let avatarProfile: CGFloat = 72     // Profile identity monogram
    static let feedAvatar: CGFloat = 36        // FeedCard source avatar

    // MARK: Fan Zone game card
    static let gameCardWidth: CGFloat = 170
    static let gameCardHeight: CGFloat = 138

    // MARK: Hairlines
    static let hairline: CGFloat = 1
}
