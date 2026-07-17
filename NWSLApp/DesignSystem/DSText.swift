//
//  DSText.swift
//  NWSLApp
//
//  Typography helpers for the design-token system — the recurring text motifs
//  from `tokens/typography.css` and the screen specs, expressed as SwiftUI
//  modifiers so callsites stay terse and consistent.
//

import SwiftUI

// MARK: - Dynamic Type

/// A system font whose point size scales with the user's text-size setting (Dynamic
/// Type), capped app-wide at the root (see `RootTabView`'s `.dynamicTypeSize`). The
/// base `size` is the value at the DEFAULT text setting, so a migrated call site looks
/// identical to the old fixed `.font(.system(size:))` at default and grows/shrinks from
/// there. Defaults to scaling relative to `.body` — the SAME axis crests scale on (see
/// `TeamLogo`), so paired text + crest move in lockstep.
struct DSScaledFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design
    private let monospacedDigit: Bool

    init(size: CGFloat,
         weight: Font.Weight,
         design: Font.Design,
         relativeTo: Font.TextStyle,
         monospacedDigit: Bool) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: relativeTo)
        self.weight = weight
        self.design = design
        self.monospacedDigit = monospacedDigit
    }

    func body(content: Content) -> some View {
        let base = Font.system(size: size, weight: weight, design: design)
        return content.font(monospacedDigit ? base.monospacedDigit() : base)
    }
}

extension View {
    /// Dynamic-Type-scaling replacement for `.font(.system(size:weight:design:))`.
    /// `size` is the size at the default text setting. Migration is mechanical:
    /// `.font(.system(size: 14, weight: .bold))` → `.dsFont(14, weight: .bold)`.
    func dsFont(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        relativeTo: Font.TextStyle = .body,
        monospacedDigit: Bool = false
    ) -> some View {
        modifier(DSScaledFont(size: size,
                              weight: weight,
                              design: design,
                              relativeTo: relativeTo,
                              monospacedDigit: monospacedDigit))
    }

    /// MatchDetail header score — 44pt heavy with tabular figures so a "2 – 1" never
    /// jitters as digits change on a live refresh; scales with Dynamic Type. Replaces
    /// the former static `Font.dsScore` (a stored `Font` can't scale).
    func dsScoreFont() -> some View {
        dsFont(44, weight: .heavy, monospacedDigit: true)
    }
}

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
            .dsFont(size, weight: weight)
            .tracking(tracking)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }

    /// Home-module / screen-section title — 20pt bold, primary.
    func sectionTitle() -> some View {
        self
            .dsFont(20, weight: .bold)
            .foregroundStyle(Color.dsFgPrimary)
    }
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
    /// The bare chevron comes for free from the PARENT carrying no nav title: tab roots
    /// hide the bar and set none, so iOS's default back button has no parent-title text to
    /// draw beside the chevron. We deliberately do NOT use `.toolbarRole(.editor)` to force
    /// this — CLAUDE.md bans it because it breaks the edge-swipe-back gesture.
    func nativeBackButton(title: String? = nil) -> some View {
        self
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(title ?? "")   // "" renders no title (identity-header screens)
    }
}
