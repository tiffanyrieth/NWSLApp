//
//  TierBadge.swift
//  NWSLApp
//
//  The Superfan tier badge (Fan Zone Competitive Redesign, PR1) — a reusable rounded-rect badge rendering
//  a tier's SF Symbol in its tier color, at any size. Extracted from the inline capsule that used to live
//  in SuperfanDetailView so the carousel card, detail hero, season-history rows, and any future surface
//  all render the same mark. Sizes span the design's three uses: small (~24, carousel + history rows),
//  medium (~40), large (80, the detail hero, which gains a glow).
//
//  Structure per the handoff: rounded rect at 28% corner radius, tier-color 18% fill, 1.5pt tier-color
//  40% border, glow shadow at large sizes. The icon is ~half the badge size.
//

import SwiftUI

struct TierBadge: View {
    let tier: SuperfanTier
    var size: CGFloat = 40

    private var iconSize: CGFloat { size * 0.5 }
    /// Glow only reads at hero scale; below that it muddies the small badges.
    private var showsGlow: Bool { size >= 60 }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(tier.color.opacity(0.18))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(tier.color.opacity(0.40), lineWidth: 1.5)
            )
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: tier.symbol)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(tier.color)
            )
            .shadow(color: showsGlow ? tier.color.opacity(0.25) : .clear,
                    radius: showsGlow ? size * 0.35 : 0)
            .accessibilityElement()
            .accessibilityLabel("\(tier.label) tier")
    }
}

#if DEBUG
#Preview {
    HStack(spacing: 20) {
        ForEach(SuperfanTier.allCases, id: \.self) { tier in
            VStack(spacing: 12) {
                TierBadge(tier: tier, size: 24)
                TierBadge(tier: tier, size: 40)
                TierBadge(tier: tier, size: 80)
                Text(tier.label).dsFont(12)
            }
        }
    }
    .padding(40)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.dsBgGrouped)
}
#endif
