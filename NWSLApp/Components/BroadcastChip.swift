//
//  BroadcastChip.swift
//  NWSLApp
//
//  A color-coded broadcast pill (design-handoff §0 "Broadcast color chips"):
//  a tinted dot + the partner name, in the partner's brand color over a faint
//  wash. Replaces the old "📺 text" on schedule cards (and, at screen #2, match
//  detail). The color map is the handoff's canonical broadcast palette, matched
//  by substring like BroadcastLink so ESPN's free-text channel names resolve.
//
//  NOTE: kept separate from the existing `BroadcastInfo` color DB (whose hues
//  predate this palette) so the Schedule redesign stays isolated; the two unify
//  when Match Detail is reworked.
//

import SwiftUI

struct BroadcastChip: View {
    let name: String
    /// The small variant used on dense schedule cards (10pt). Match Detail can pass
    /// `small: false` for the roomier header chip later.
    var small: Bool = true

    private var color: Color { Self.color(for: name) }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(name)
                .dsFont(small ? 10 : 11, weight: .bold)
                .tracking(0.4)
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, small ? 8 : 9)
        .padding(.vertical, small ? 2 : 3)
        .background(color.opacity(0.14), in: Capsule())
    }

    /// Broadcast partner color — resolves through the single `BroadcastBrand` source
    /// (kept as a static accessor here for the existing callers: HowToWatchCard, ComingUpRow).
    static func color(for name: String) -> Color { BroadcastBrand.color(for: name) }
}

#Preview {
    VStack(spacing: 10) {
        BroadcastChip(name: "Prime Video")
        BroadcastChip(name: "ESPN")
        BroadcastChip(name: "Paramount+")
        BroadcastChip(name: "ION")
        BroadcastChip(name: "Victory+")
    }
    .padding()
    .background(Color.dsBgCard)
}
