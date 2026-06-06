//
//  SocialLinkButton.swift
//  NWSLApp
//
//  One social account in the TeamDetailView header's social row: a 36pt circular
//  icon tinted in the club's accent color, with the platform name below. Tapping
//  opens the account in its app (or the browser) via the environment openURL — the
//  same mechanism TeamContentCard / FeedCard use for external links.
//
//  Design (approved): the circles take the CLUB's accent color rather than five
//  platform brand colors, so the row stays cohesive with the rest of the
//  team-colored page (player cards, jersey badges) and "breathes" instead of
//  reading as a loud rainbow. The label under each icon carries the platform
//  identity, so a monochrome glyph is enough — SF Symbols has no brand logos
//  anyway (these approximate, matching the app's existing platform-glyph
//  convention in TeamContentItem.Platform).
//

import SwiftUI

struct SocialLinkButton: View {
    let link: SocialLink
    /// The club's accent hex (from the roster payload). nil falls back to the app
    /// accent via Color.teamAccent.
    let accentHex: String?

    @Environment(\.openURL) private var openURL

    var body: some View {
        let accent = Color.teamAccent(hex: accentHex)
        Button {
            openURL(link.url)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: link.platform.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accent.on)
                    .frame(width: 36, height: 36)
                    .background(accent.fill, in: Circle())
                Text(link.platform.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(link.platform.label) — open")
    }
}
