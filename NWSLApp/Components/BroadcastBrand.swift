//
//  BroadcastBrand.swift
//  NWSLApp
//
//  The SINGLE source of truth for a broadcast partner's brand color, matched by
//  substring against ESPN's free-text channel name (e.g. "ESPN", "ESPN2", "ABC",
//  "Prime Video", "CBS Sports"). Both the schedule/match `BroadcastChip` and the
//  "How to Watch" `BroadcastInfo` resolve through this, so a partner reads the same
//  color everywhere.
//
//  Previously the palette lived twice — in BroadcastChip and (as a since-dead field)
//  in BroadcastInfo — with divergent hex. Canonical values chosen by the owner
//  (2026-07-17): ESPN/ABC bright red (not the deeper material red), CBS broadcast
//  blue (not Google blue), ION its true purple (not red), Victory+ teal (not green —
//  which would have collided with the NEWS pill's #30D158).
//

import SwiftUI

enum BroadcastBrand {
    static func color(for name: String) -> Color {
        let n = name.lowercased()
        switch true {
        case n.contains("prime"), n.contains("amazon"): return Color(hex: "#00A8E1")  // Prime Video
        case n.contains("espn"), n.contains("abc"):     return Color(hex: "#E0203B")  // ESPN/ABC — bright red
        case n.contains("paramount"):                   return Color(hex: "#0064FF")  // Paramount+
        case n.contains("cbs"):                         return Color(hex: "#1FA0E0")  // CBS — broadcast blue
        case n.contains("ion"):                         return Color(hex: "#6B4EFF")  // ION — purple
        case n.contains("victory"):                     return Color(hex: "#15B7B0")  // Victory+ — teal
        case n.contains("nwsl"):                        return Color(hex: "#FF6B9D")  // NWSL+
        default:                                        return .dsFgSecondary          // unknown → neutral
        }
    }
}
