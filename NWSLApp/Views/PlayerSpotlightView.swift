//
//  PlayerSpotlightView.swift
//  NWSLApp
//
//  The spotlight tap-through (Reference/Design/spotlight-design-spec.md §Tap-
//  through) — pushed from a Home Module 2 card. Its own narrative experience:
//  the video up top (opens the source), then an extended profile (nationality /
//  age / position, career highlights, fun facts, and season form when a live
//  stats source exists). Deliberately NOT PlayerDetailView — spotlight is "meet
//  this person," PlayerDetail is "what are their stats." They can be linked once
//  PlayerDetail has real content.
//
//  Rides the pushing tab's NavigationStack (no own stack), so the nav bar back
//  button is the explicit back affordance. The video hero loads the real YouTube
//  thumbnail (spotlight.thumbnailURL, designed-crest-tile fallback), matching the
//  card. The jersey badge is still TEMP (app accent — Home fetches no club color);
//  a content backend brings the team color.
//

import SwiftUI

struct PlayerSpotlightView: View {
    let spotlight: PlayerSpotlight
    /// Resolved from the followed Club directory (crest + name). Optional so a
    /// missing match still renders the written profile.
    let club: Club?
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if spotlight.videoURL != nil {
                    videoHero
                }
                header
                Text(spotlight.bioBlurb)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                if !spotlight.careerHighlights.isEmpty {
                    bulletSection("Career highlights", spotlight.careerHighlights)
                }
                if !spotlight.funFacts.isEmpty {
                    bulletSection("Did you know", spotlight.funFacts)
                }
                if let form = spotlight.seasonForm {
                    bulletSection("This season", [form])
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(spotlight.playerName)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Video hero (designed tile — opens the source)

    private var videoHero: some View {
        Button {
            if let url = spotlight.videoURL { openURL(url) }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    heroBackground
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.white.opacity(0.95))
                        .shadow(radius: 6)
                }
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                if let title = spotlight.videoTitle {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                }
                if let source = spotlight.videoSource {
                    Text("Watch on \(source)")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// Real video frame when available, else the designed crest tile (also covers
    /// AsyncImage's loading/failure phases).
    @ViewBuilder
    private var heroBackground: some View {
        if let thumbnailURL = spotlight.thumbnailURL {
            AsyncImage(url: thumbnailURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    heroTile
                }
            }
        } else {
            heroTile
        }
    }

    private var heroTile: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.systemGray5), Color(.systemGray4)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            TeamLogo(urlString: club?.logoURL, size: 72)
                .opacity(0.9)
        }
    }

    // MARK: - Header (jersey badge + identity line)

    private var header: some View {
        HStack(spacing: 16) {
            jerseyBadge
            VStack(alignment: .leading, spacing: 4) {
                Text(spotlight.playerName)
                    .font(.title2.weight(.bold))
                Text("\(spotlight.position) · \(teamName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let identity = identityLine {
                    Text(identity)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var jerseyBadge: some View {
        let accent = Color.teamAccent(hex: nil)   // TEMP: no Club hex — app accent
        return ZStack {
            Circle().fill(accent.fill)
            Text("\(spotlight.jerseyNumber)")
                .font(.title.weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(accent.on)
        }
        .frame(width: 64, height: 64)
    }

    /// "Iceland · Age 25" — joins whichever of nationality/age we have.
    private var identityLine: String? {
        var parts: [String] = []
        if let nationality = spotlight.nationality { parts.append(nationality) }
        if let age = spotlight.age { parts.append("Age \(age)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Bulleted profile section

    private func bulletSection(_ title: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 5))
                            .foregroundStyle(.secondary)
                        Text(item)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var teamName: String {
        club?.shortName ?? club?.displayName ?? spotlight.teamAbbreviation
    }
}
