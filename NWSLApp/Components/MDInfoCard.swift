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

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .trackedCaps(size: 10, tracking: 0.6, color: .dsFgSecondary)
            Text(value)
                .dsFont(13, weight: .semibold)
                .foregroundStyle(Color.dsFgPrimary)
                // Reserve two lines so a long Venue and a one-word Broadcast keep the
                // SAME card height — the grid stays even (bug #8). Shrink-to-fit the
                // longest values (e.g. "Audi Field, Washington, D.C.") rather than truncate.
                .lineLimit(2, reservesSpace: true)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.dsMdCard)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusLg, style: .continuous))
    }
}
