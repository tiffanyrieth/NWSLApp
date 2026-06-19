//
//  Chip.swift
//  NWSLApp
//
//  A pill-shaped filter chip (design handoff `UIComponents.jsx` → `UIChip`):
//  active = accent fill / white text, inactive = card fill / primary text.
//  Used by the Schedule filter bar (NWSL · My teams · All) and the Feed chip bar
//  (All · per-team · League). One source of truth for the chip's shape + states.
//

import SwiftUI

struct Chip: View {
    let label: String
    var isActive: Bool = false
    /// Optional leading dot (e.g. a team color on a Feed per-team chip).
    var dotColor: Color? = nil
    /// Tighter sizing (13pt / less vertical padding) for the redesigned Schedule
    /// filter bar. Defaults to the original look so existing callers are unchanged.
    var compact: Bool = false
    /// The fill when active — defaults to the app accent. Home's per-team chips pass
    /// each club's own color so the active chip carries its team identity (home.jsx).
    var activeColor: Color = .dsAccent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.space3) {
                if let dotColor {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 7, height: 7)
                }
                Text(label)
                    .font(.system(size: compact ? 13 : 15, weight: compact ? .semibold : .medium))
                    .lineLimit(1)
                    // Scale down rather than truncate if a chip is ever width-constrained
                    // (a no-op in the scrolling chip bars, a safety net at large text).
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, DS.chipPaddingH)
            .padding(.vertical, compact ? 6 : DS.chipPaddingV)
            .background(isActive ? activeColor : Color.dsBgCard)
            .foregroundStyle(isActive ? Color.white : Color.dsFgPrimary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    HStack(spacing: 8) {
        Chip(label: "NWSL", isActive: true) {}
        Chip(label: "My teams") {}
        Chip(label: "Spirit", dotColor: .dsStateLive) {}
    }
    .padding()
    .background(Color.dsBgGrouped)
}
