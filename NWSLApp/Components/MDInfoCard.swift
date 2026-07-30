//
//  MDInfoCard.swift
//  NWSLApp
//
//  One tile in the future-match info grid (design handoff `match-detail.jsx` →
//  the `Info` tiles): a tracked-caps label over a value, left-aligned on the card
//  surface — no emoji (the redesign drops the icons). Used for Venue / Broadcast /
//  Competition. (Past-match kickoff weather ships as a header stamp; a future-match
//  forecast tile here is deferred to the forecast build.)
//

import SwiftUI

struct MDInfoCard: View {
    let label: String
    let value: String

    /// Capped at AX1 app-wide (`RootTabView`), so this is true at exactly one size.
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .trackedCaps(size: 10, tracking: 0.6, color: .dsFgSecondary)
            valueText
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.dsMdCard)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusLg, style: .continuous))
    }

    /// The tile's value, clamped differently at accessibility sizes.
    ///
    /// BELOW them: two reserved lines + shrink-to-fit, so a long Venue and a one-word Broadcast
    /// keep the SAME card height and the three-across grid stays even (bug #8).
    ///
    /// AT them (2026-07-29): the caller stacks the tiles full-width instead of three-across, so
    /// there are no siblings to match heights with — the reservation stops earning its keep and
    /// starts costing the value the room it needs ("CPKC Stadium,…"). Wrap freely instead.
    @ViewBuilder
    private var valueText: some View {
        let base = Text(value)
            .dsFont(13, weight: .semibold)
            .foregroundStyle(Color.dsFgPrimary)
        if typeSize.isAccessibilitySize {
            base.fixedSize(horizontal: false, vertical: true)
        } else {
            base.lineLimit(2, reservesSpace: true).minimumScaleFactor(0.8)
        }
    }
}
