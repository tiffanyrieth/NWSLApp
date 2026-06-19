//
//  PlayerSpotlightCard.swift
//  NWSLApp
//
//  Home's Module 2 ("Weekly Player Spotlight") — a big (~400pt) CONTAINED
//  team-gradient card, the section anchor:
//   • The team-color gradient fills the card.
//   • The player's headshot sits in the right ~half, soft-masked with a wide
//     horizontal fade so its studio background dissolves seamlessly into the
//     gradient (no vertical seam). Display area ≈ half the card, so the 480px
//     Cloudinary source renders ~3× — crisp.
//   • ALL text lives in a dedicated left zone over the gradient — a "GET TO KNOW"
//     eyebrow, the name, "#num · position · Club", a 2-line teaser, and a "Read her
//     story →" pill — fully legible and never over the player's face.
//   • No headshot AVAILABLE → the ghosted jersey-number + crest fallback.
//
//  Headshot resolution is a tri-state (`PhotoState`): the player's NWSL GUID may
//  map in the shared HeadshotStore yet the NWSL CDN may have no image on file (a
//  404). So we only show the photo once it actually decodes; a missing GUID OR a
//  404 both fall back to the ghost+crest treatment — the card is never empty.
//  Wrapped in a NavigationLink by HomeView.
//
//  Team color: the eyebrow/meta use the club's dark-legible accent
//  (Club.accentColor); the "Read her story" pill uses the club's brand fill + a
//  legible on-color (Color.teamAccent). Falls back to the app accent when unresolved.
//

import SwiftUI
import UIKit

struct PlayerSpotlightCard: View {
    let spotlight: PlayerSpotlight
    /// Resolved from the followed Club directory by abbreviation (crest + colors).
    let club: Club?

    /// The card's fixed height — the tallest card on Home, by design (the anchor).
    static let heroHeight: CGFloat = 400

    /// loading → just the gradient (no flash); loaded → the photo; missing (no GUID
    /// or a CDN 404) → the ghost+crest fallback. Never an empty card.
    private enum PhotoState: Equatable {
        case loading
        case loaded(UIImage)
        case missing
    }
    @State private var photoState: PhotoState = .loading

    /// Dark-legible team accent for the eyebrow / meta.
    private var accent: Color { club?.accentColor ?? .dsAccent }
    /// Team-brand fill + on-color for the "Read her story" pill.
    private var pill: (fill: Color, on: Color) { Color.teamAccent(hex: club?.brandHex) }

    /// The Cloudinary headshot URL (largest verified width), or nil when the player
    /// isn't mapped — read here so the load re-fires once the @Observable map loads.
    private var photoURL: URL? {
        guard let guid = HeadshotStore.shared.guid(forAthleteID: spotlight.espnAthleteId) else { return nil }
        return AppConfig.headshotImageURL(guid: guid, size: .detail)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                teamGradient
                photoOrFallback(cardWidth: geo.size.width)
                bottomScrim
                editorial
                    .frame(maxWidth: geo.size.width * 0.60, alignment: .leading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(18)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(height: Self.heroHeight)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusXxl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusXxl, style: .continuous)
                .stroke(accent.opacity(0.35), lineWidth: 1)
        )
        // Re-keyed on the URL so it reloads when HeadshotStore's map arrives.
        .task(id: photoURL) { await resolvePhoto() }
    }

    private func resolvePhoto() async {
        guard let url = photoURL else { photoState = .missing; return }
        if let hit = ImageCache.shared.cached(url) { photoState = .loaded(hit); return }
        photoState = .loading
        if let img = await ImageCache.shared.image(for: url) {
            photoState = .loaded(img)
        } else {
            photoState = .missing   // CDN has no photo for this mapped player
        }
    }

    // MARK: - Background

    /// Navy base + an accent wash gathered in the top-right (around the photo) and
    /// kept clear of the bottom-left text zone, so the eyebrow/name stay legible.
    private var teamGradient: some View {
        ZStack {
            Color(hex: "#14151C")
            LinearGradient(
                colors: [accent.opacity(0.60), accent.opacity(0.0)],
                startPoint: .topTrailing, endPoint: .bottomLeading
            )
        }
    }

    /// A bottom scrim so the text block reads on any wash or photo shoulder.
    private var bottomScrim: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.42),
                .init(color: Color(hex: "#08090C").opacity(0.88), location: 1.0)
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    // MARK: - Photo / fallback

    @ViewBuilder
    private func photoOrFallback(cardWidth: CGFloat) -> some View {
        switch photoState {
        case .loaded(let img): photo(img, cardWidth: cardWidth)
        case .missing:         ghostFallback
        case .loading:         Color.clear   // gradient only while resolving (no flash)
        }
    }

    /// The headshot in the right ~64%, with a WIDE horizontal fade: the left ~42% of
    /// the photo dissolves into the gradient, so there's no hard vertical seam — the
    /// studio background melts away regardless of the source crop.
    private func photo(_ img: UIImage, cardWidth: CGFloat) -> some View {
        let w = cardWidth * 0.64
        return Image(uiImage: img)
            .resizable()
            .scaledToFill()
            .frame(width: w, height: Self.heroHeight)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .clipped()
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black, location: 0.42)
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: w)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            )
            .allowsHitTesting(false)
    }

    private var ghostFallback: some View {
        ZStack {
            Text("\(spotlight.jerseyNumber)")
                .dsFont(200, weight: .heavy, monospacedDigit: true)
                .foregroundStyle(.white.opacity(0.06))
            if let logo = club?.logoURL {
                TeamLogo(urlString: logo, teamAbbreviation: club?.abbreviation, size: 96)
                    .opacity(0.42)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Text zone (left)

    private var editorial: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Get to know")
                .trackedCaps(size: 11, tracking: 1.5, color: accent)
            Text(spotlight.playerName)
                .dsFont(26, weight: .heavy)
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            Text(metaLine)
                .dsFont(13, monospacedDigit: true)
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
                .padding(.top, 5)
            Text(spotlight.bioBlurb)
                .dsFont(13.5)
                .lineSpacing(2)
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            readPill
                .padding(.top, 13)
        }
    }

    /// "#21 · Forward · Angel City FC" — single-player subject → full club name.
    private var metaLine: String {
        "#\(spotlight.jerseyNumber) · \(spotlight.position) · \(club?.displayName ?? spotlight.teamAbbreviation)"
    }

    private var readPill: some View {
        HStack(spacing: 5) {
            Text("Read her story")
            Text("→")
        }
        .dsFont(14, weight: .semibold)
        .foregroundStyle(pill.on)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(pill.fill, in: Capsule())
    }
}
