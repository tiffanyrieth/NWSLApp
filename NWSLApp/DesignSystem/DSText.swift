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
    /// A left-aligned context label right next to the back chevron on a PUSHED
    /// screen — a "where am I" navigation reminder ("‹ Teams", "‹ Match Details"),
    /// not a centered title. Suppresses the inherited parent-title text on the back
    /// button (just the chevron) so the label reads cleanly. Tab roots keep their
    /// large left-aligned titles; this is only for drilled-in screens.
    func navigationContextLabel(_ label: String) -> some View {
        self
            .navigationBarTitleDisplayMode(.inline)
            // `.editor` role renders the back button as a bare chevron (no inherited
            // parent-title text), so the label below reads "‹ Label" cleanly while
            // the edge-swipe-back gesture still works.
            .toolbarRole(.editor)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text(label)
                        .font(.headline)
                        .foregroundStyle(Color.dsFgPrimary)
                        .lineLimit(1)
                        .fixedSize()   // render at full width — toolbar text truncates otherwise
                }
            }
    }
}
