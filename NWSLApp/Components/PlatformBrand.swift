//
//  PlatformBrand.swift
//  NWSLApp
//
//  The SINGLE source of truth for a social platform's brand style — a solid color, or
//  for Instagram its authentic 45° gradient. Both the content-card `PlatformBadge` glyph
//  and the Team-page social-link glyphs resolve through this, so a platform reads the
//  same everywhere. (`AnyShapeStyle` so the same value works as a tile fill and as a
//  `.foregroundStyle` icon tint, including the gradient.)
//
//  Previously the palette lived twice with divergent hex (PlatformBadge + TeamDetail's
//  socialColor). Canonical values chosen by the owner (2026-07-17): true YouTube red,
//  Bluesky brand blue, TikTok's teal accent (its true black vanishes on the dark canvas),
//  Instagram's real gradient (works as a glyph tint, so no flat-pink fallback needed),
//  Reddit orange.
//

import SwiftUI

enum PlatformBrand {
    static let youtube   = AnyShapeStyle(Color(hex: "#FF0000"))
    static let bluesky   = AnyShapeStyle(Color(hex: "#0085FF"))
    static let tiktok    = AnyShapeStyle(Color(hex: "#25C9D6"))
    static let reddit    = AnyShapeStyle(Color(hex: "#FF4500"))
    static let article   = AnyShapeStyle(Color.dsFgTertiary)   // #636366 — neutral, not a brand
    static let instagram = AnyShapeStyle(LinearGradient(
        colors: [Color(hex: "#515BD4"), Color(hex: "#8134AF"),
                 Color(hex: "#DD2A7B"), Color(hex: "#FEDA77")],
        startPoint: .topLeading, endPoint: .bottomTrailing))
}
