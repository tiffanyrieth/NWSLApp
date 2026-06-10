//
//  MDInfoCard.swift
//  NWSLApp
//
//  One tile in the future-match info grid (design handoff `MatchDetailParts.jsx`
//  → `MDInfoCard`): an emoji, a tracked-caps label, and a value, on the match-
//  detail card surface. Used for Venue / Broadcast / Competition (weather is
//  deferred — see CLAUDE.md What's-Next).
//

import SwiftUI

struct MDInfoCard: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 6) {
            Text(icon).font(.system(size: 20))
            Text(label)
                .trackedCaps(size: 9, tracking: 1, color: .dsFgTertiary)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.dsFgPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .background(Color.dsMdCard)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusLg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusLg, style: .continuous)
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
        )
    }
}
