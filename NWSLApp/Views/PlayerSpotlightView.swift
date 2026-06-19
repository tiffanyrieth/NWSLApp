//
//  PlayerSpotlightView.swift
//  NWSLApp
//
//  The spotlight tap-through (design handoff `SpotlightScreen.jsx`), pushed from a
//  Home Module 2 card — an "Olympics-style" weekly player feature. A hero (ghosted
//  jersey number, "PLAYER OF THE WEEK", split-name typography, meta), a This-Season
//  stat grid, a Story card, Fast Facts, and a Watch video card.
//
//  Deliberately NOT PlayerDetailView — the spotlight is narrative ("meet this
//  person"); PlayerDetail is reference ("what are their stats"). Rides the pushing
//  tab's NavigationStack, so the nav bar back button is the back affordance.
//
//  Team color comes from the design palette via the resolved Club (Club.accentColor
//  for the dark-legible accent; Color.teamAccent(hex: brandHex) for the jersey
//  badge fill + on-color). The video hero loads the real YouTube frame with a
//  crest-tile fallback. "This Season" renders only when the proxy supplied real
//  season stats (online-only: real stats or the section is hidden — never fabricated).
//

import SwiftUI

struct PlayerSpotlightView: View {
    let spotlight: PlayerSpotlight
    /// Resolved from the followed Club directory (crest + colors). Optional so a
    /// missing match still renders the written profile.
    let club: Club?
    @Environment(\.openURL) private var openURL

    private var accent: Color { club?.accentColor ?? .dsAccent }
    private var jersey: (fill: Color, on: Color) { Color.teamAccent(hex: club?.brandHex) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero
                thisSeason
                story
                fastFacts
                watch
            }
            .padding(20)
        }
        .background(Color.dsBgGrouped)
        .nativeBackButton(title: "Player Spotlight")
    }

    // MARK: - Hero (ghosted number + eyebrow + split name + meta)

    private var hero: some View {
        ZStack(alignment: .topTrailing) {
            Text("\(spotlight.jerseyNumber)")
                .dsFont(120, weight: .heavy, monospacedDigit: true)
                .foregroundStyle(.white.opacity(0.06))
                .offset(x: 8, y: -18)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 16) {
                Text("Player of the week")
                    .trackedCaps(size: 11, tracking: 1.5, color: accent)

                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(jersey.fill)
                        Text("\(spotlight.jerseyNumber)")
                            .dsFont(20, weight: .heavy, monospacedDigit: true)
                            .foregroundStyle(jersey.on)
                    }
                    .frame(width: 52, height: 52)

                    VStack(alignment: .leading, spacing: 0) {
                        if !nameParts.first.isEmpty {
                            Text(nameParts.first)
                                .dsFont(22, weight: .medium)
                                .foregroundStyle(Color.dsFgSecondary)
                        }
                        Text(nameParts.last)
                            .dsFont(30, weight: .bold)
                            .foregroundStyle(Color.dsFgPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                metaRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var metaRow: some View {
        HStack(spacing: 6) {
            Text(spotlight.position)
            dot
            Text(spotlight.teamAbbreviation).foregroundStyle(accent)
            if let age = spotlight.age {
                dot
                Text("Age \(age)")
            }
        }
        .dsFont(13, weight: .medium)
        .foregroundStyle(Color.dsFgSecondary)
    }

    private var dot: some View {
        Circle().fill(Color.dsFgQuaternary).frame(width: 3, height: 3)
    }

    // MARK: - This Season (3-col stat grid)

    // Online-only: rendered ONLY when the proxy supplied real season stats. On a
    // best-effort miss (`statStrip == nil`) the section is simply absent — no
    // fabricated numbers (the narrative-first spotlight reads fine without it).
    @ViewBuilder
    private var thisSeason: some View {
        if let s = spotlight.statStrip {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("This Season")
                HStack(spacing: 12) {
                    seasonStat("\(s.goals)", "Goals", highlight: true)
                    seasonStat("\(s.assists)", "Assists")
                    seasonStat("\(s.apps)", "Apps")
                }
            }
        }
    }

    private func seasonStat(_ value: String, _ label: String, highlight: Bool = false) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .dsFont(28, weight: .bold, monospacedDigit: true)
                .foregroundStyle(highlight ? accent : Color.dsFgPrimary)
            Text(label)
                .dsFont(12)
                .foregroundStyle(Color.dsFgSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.dsBgCard)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusLg, style: .continuous))
    }

    // MARK: - The Story

    private var story: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("The Story")
            Text(spotlight.bioBlurb)
                .dsFont(15)
                .lineSpacing(4)
                .foregroundStyle(Color.dsFgPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.dsBgCard)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusLg, style: .continuous))
    }

    // MARK: - Fast Facts

    @ViewBuilder
    private var fastFacts: some View {
        let facts = spotlight.careerHighlights + spotlight.funFacts
        if !facts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Fast Facts")
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(facts, id: \.self) { fact in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("★")
                                .dsFont(11)
                                .foregroundStyle(accent)
                            Text(fact)
                                .dsFont(14)
                                .foregroundStyle(Color.dsFgPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.dsBgCard)
                .clipShape(RoundedRectangle(cornerRadius: DS.radiusLg, style: .continuous))
            }
        }
    }

    // MARK: - Watch (video card)

    @ViewBuilder
    private var watch: some View {
        if spotlight.videoURL != nil {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Watch")
                Button {
                    if let url = spotlight.videoURL { openURL(url) }
                } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        ZStack {
                            heroBackground
                            Image(systemName: "play.circle.fill")
                                .dsFont(52)
                                .foregroundStyle(.white.opacity(0.95))
                                .shadow(radius: 6)
                        }
                        .frame(height: 190)
                        .frame(maxWidth: .infinity)
                        .clipped()

                        VStack(alignment: .leading, spacing: 4) {
                            if let title = spotlight.videoTitle {
                                Text(title)
                                    .dsFont(15, weight: .semibold)
                                    .foregroundStyle(Color.dsFgPrimary)
                                    .multilineTextAlignment(.leading)
                            }
                            if let source = spotlight.videoSource {
                                Text("Watch on \(source)")
                                    .dsFont(13, weight: .semibold)
                                    .foregroundStyle(accent)
                            }
                        }
                        .padding(14)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.dsBgCard)
                    .clipShape(RoundedRectangle(cornerRadius: DS.radiusLg, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Real video frame when available, else the designed crest tile.
    @ViewBuilder
    private var heroBackground: some View {
        if let thumbnailURL = spotlight.thumbnailURL {
            // CachedThumbnail (not bare AsyncImage) so the hero frame goes through the shared
            // ImageCache → disk cache, and doesn't re-download on every recreation.
            CachedThumbnail(url: thumbnailURL) { heroTile }
        } else {
            heroTile
        }
    }

    private var heroTile: some View {
        ZStack {
            LinearGradient(colors: [Color.dsBgTertiary, Color.dsBgCard],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            TeamLogo(urlString: club?.logoURL, teamAbbreviation: club?.abbreviation, size: 72).opacity(0.9)
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title).dsFont(17, weight: .bold).foregroundStyle(Color.dsFgPrimary)
    }

    /// Split the name into a first line + a bold last line. A single-word name
    /// goes entirely on the bold line.
    private var nameParts: (first: String, last: String) {
        let words = spotlight.playerName.split(separator: " ").map(String.init)
        guard words.count > 1 else { return ("", spotlight.playerName) }
        return (words[0], words.dropFirst().joined(separator: " "))
    }
}
