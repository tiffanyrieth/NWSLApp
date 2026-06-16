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
                .font(.system(size: small ? 10 : 11, weight: .bold))
                .tracking(0.4)
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, small ? 8 : 9)
        .padding(.vertical, small ? 2 : 3)
        .background(color.opacity(0.14), in: Capsule())
    }

    /// The handoff's broadcast palette, matched by substring against ESPN's
    /// free-text channel name (e.g. "ESPN", "Prime Video", "Paramount+").
    static func color(for name: String) -> Color {
        let n = name.lowercased()
        switch true {
        case n.contains("prime"), n.contains("amazon"): return Color(hex: "#00A8E1")
        case n.contains("espn"), n.contains("abc"):     return Color(hex: "#E0203B")
        case n.contains("paramount"):                   return Color(hex: "#0064FF")
        case n.contains("cbs"):                         return Color(hex: "#1FA0E0")
        case n.contains("ion"):                         return Color(hex: "#E4322B")
        case n.contains("victory"):                     return Color(hex: "#15B7B0")
        case n.contains("nwsl"):                        return Color(hex: "#FF6B9D")
        default:                                        return .dsFgSecondary
        }
    }
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
