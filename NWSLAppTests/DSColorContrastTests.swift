//
//  DSColorContrastTests.swift
//  NWSLAppTests
//
//  THE CONTRAST FLOOR, made mechanical (owner 2026-08-11) — the color-axis peer of the 12pt font
//  floor. Every READABLE-TEXT foreground token must clear WCAG AA against every surface it can sit
//  on. A future session that re-dims a text token to a prettier-but-darker gray fails here, the way
//  a sub-12pt readable font fails the font audit.
//
//  Background: the app shipped dark-on-dark text — `dsFgSecondary` #8E8E93 was 4.27:1 on a card
//  (under AA), and tertiary/quaternary were used as text at 2.33:1 / 1.53:1 (near-invisible). The
//  fix lightened secondary to #AEAEB2 and made tertiary/quaternary DECORATION-ONLY. These tests lock
//  that in. Decoration tokens are intentionally NOT asserted — they're exempt by definition (a
//  hairline needn't be readable).
//
//  The hex constants mirror DSColor.swift. They're duplicated here (not read from Color) because the
//  WCAG math needs the source hex, and pinning the literals means a value change must consciously
//  update BOTH places — which is the point of a floor.
//

import Foundation
import SwiftUI
import Testing
@testable import NWSLApp

struct DSColorContrastTests {

    // Readable-text tokens — the ONLY ones allowed to carry text the user reads.
    private let readableText: [(name: String, hex: String)] = [
        ("dsFgPrimary", "#FFFFFF"),
        ("dsFgSecondary", "#AEAEB2"),
    ]

    // Every surface readable text can land on.
    private let surfaces: [(name: String, hex: String)] = [
        ("dsBgPrimary", "#000000"),
        ("dsBgGrouped", "#1C1C1E"),
        ("dsBgCard", "#2C2C2E"),
        ("dsBgTertiary", "#3A3A3C"),
        ("dsMdPanel", "#14151C"),
        ("dsMdCard", "#1A1C23"),
    ]

    /// WCAG AA for normal text. The whole point of the fix — no readable token may fall below this
    /// on any surface, so hierarchy is expressed by weight/size, never a token that fails somewhere.
    private let aa = 4.5

    @Test func everyReadableTokenClearsAAOnEverySurface() {
        for fg in readableText {
            for bg in surfaces {
                let ratio = Color.wcagContrastRatio(fg.hex, bg.hex)
                #expect(ratio != nil, "malformed hex: \(fg.name) / \(bg.name)")
                #expect((ratio ?? 0) >= aa,
                        "\(fg.name) on \(bg.name) = \(String(format: "%.2f", ratio ?? 0)):1 — below WCAG AA \(aa):1")
            }
        }
    }

    /// The exemplar surface: the #2C2C2E card the weather footer + most Fan Zone text sits on.
    /// This is the pairing that was broken; pin its exact numbers so a regression is obvious.
    @Test func theCardSurfaceThatWasBroken() {
        #expect((Color.wcagContrastRatio("#AEAEB2", "#2C2C2E") ?? 0) >= aa)   // was 4.27 (#8E8E93) → now 6.30
        #expect((Color.wcagContrastRatio("#FFFFFF", "#2C2C2E") ?? 0) >= aa)   // primary, ~13.9
    }

    /// Guard the regression directly: the OLD secondary value would fail this suite. If someone
    /// reverts #AEAEB2 → #8E8E93, `everyReadableTokenClearsAAOnEverySurface` catches it — this test
    /// documents WHY, by asserting the old value was genuinely sub-AA on a card.
    @Test func theOldSecondaryValueWasBelowAAOnCards() {
        let old = Color.wcagContrastRatio("#8E8E93", "#2C2C2E") ?? 0
        #expect(old < aa, "the old #8E8E93 was \(String(format: "%.2f", old)):1 on a card — the bug this floor prevents")
    }

    /// The contrast math itself: white-on-black is the WCAG maximum (21:1); identical colors are 1:1.
    @Test func contrastMathSanity() {
        #expect((Color.wcagContrastRatio("#FFFFFF", "#000000") ?? 0) > 20.9)
        #expect((Color.wcagContrastRatio("#2C2C2E", "#2C2C2E") ?? 0) == 1.0)
        #expect(Color.wcagContrastRatio("#GGGGGG", "#000000") == nil)   // malformed → nil, never a crash
    }
}
