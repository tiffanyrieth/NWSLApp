//
//  DSText.swift
//  NWSLApp
//
//  Typography helpers for the design-token system — the recurring text motifs
//  from `tokens/typography.css` and the screen specs, expressed as SwiftUI
//  modifiers so callsites stay terse and consistent.
//

import SwiftUI

extension View {
    /// The "tracked caps" motif used for section labels, tab labels, and
    /// "PLAYER OF THE WEEK"-style eyebrows: small, bold, wide letter-spacing,
    /// uppercased. Defaults to 11pt / secondary; pass `color` for a team or
    /// accent tint and `size`/`tracking` for the larger eyebrow variants.
    func trackedCaps(
        size: CGFloat = 11,
        tracking: CGFloat = 1.2,
        weight: Font.Weight = .bold,
        color: Color = .dsFgSecondary
    ) -> some View {
        self
            .font(.system(size: size, weight: weight))
            .tracking(tracking)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }

    /// Home-module / screen-section title — 20pt bold, primary.
    func sectionTitle() -> some View {
        self
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(Color.dsFgPrimary)
    }
}

extension Font {
    /// MatchDetail header score — 44pt heavy with tabular figures so a "2 – 1"
    /// never jitters as digits change on a live refresh.
    static let dsScore = Font.system(size: 44, weight: .heavy).monospacedDigit()
}

extension View {
    /// The native iOS back treatment for a PUSHED screen: a bare ‹ chevron (the native
    /// glass circle, NO word beside it) with the edge-swipe-back gesture preserved, plus
    /// — when `title` is given — the screen's own name as a centered inline navigation
    /// title. Screens whose in-content header already carries identity (MatchDetail's
    /// crests, TeamDetail's team header, PlayerDetail's name) pass no title so it isn't
    /// duplicated. Tab roots keep their custom large left-aligned headers; this is only
    /// for drilled-in screens. (Matches the MLS / The Athletic back-button treatment.)
    ///
    /// `.toolbarRole(.editor)` is what strips the inherited parent back-title down to a
    /// bare chevron WITHOUT breaking the swipe gesture (hiding the bar is the thing that
    /// breaks it) — so the title floats free of the back button as a real nav title.
    func nativeBackButton(title: String? = nil) -> some View {
        self
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(title ?? "")   // "" renders no title (identity-header screens)
    }
}
