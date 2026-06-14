//
//  PlayerHeadshot.swift
//  NWSLApp
//
//  A player's circular headshot, with the jersey-number monogram as the fallback. Drops in
//  wherever a player avatar is drawn (squad cards, player detail, Player Spotlight, the
//  formation pitch dots, Bracket matchup dots, the Predict-XI picker slots): the caller wraps
//  its existing monogram ZStack as the `fallback`, and the photo replaces the circle's fill
//  when one exists.
//
//  Mirrors TeamLogo: it resolves the player's NWSL GUID from the shared HeadshotStore, builds
//  the Cloudinary URL, and loads it through the shared in-memory ImageCache (synchronous hit
//  first → no flash on scroll-back, async fetch on a miss). A player with no photo on file
//  404s → ImageCache returns nil → the monogram stays. No GUID (unmapped, or the map hasn't
//  loaded) → the monogram stays too, and because HeadshotStore is @Observable the avatar
//  re-renders into the photo once the map finishes loading.
//
//  Any ring/stroke an avatar carries (the pitch dot's white outline, the bracket dot's team
//  ring) stays the CALLER's overlay so it frames the photo and the monogram identically; this
//  view only owns the circular fill.
//

import SwiftUI

struct PlayerHeadshot<Fallback: View>: View {
    /// The ESPN athlete id keying the headshot map. Nil (or unmapped) → the fallback shows.
    let athleteID: String?
    /// The avatar's diameter — match the monogram it replaces so the swap is seamless.
    let size: CGFloat
    /// Picks the Cloudinary width (≤48pt avatars → 240; the 96pt detail hero → 480).
    var kind: AppConfig.HeadshotSize = .card
    /// The existing monogram, shown until/unless a photo resolves.
    @ViewBuilder let fallback: () -> Fallback

    // The decoded photo, once resolved. Seeded synchronously from the cache (see body) so a
    // scrolled-back avatar paints on the first frame.
    @State private var image: UIImage?

    // Resolved during body (reads HeadshotStore.map → observed, so the view re-renders when
    // the map loads). Nil when there's no athlete id or no mapping yet.
    private var url: URL? {
        guard let guid = HeadshotStore.shared.guid(forAthleteID: athleteID) else { return nil }
        return AppConfig.headshotImageURL(guid: guid, size: kind)
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                fallback()                          // loading / no-photo / unmapped
            }
        }
        // Keyed to the URL so a recycled cell re-targets the right player, and so the avatar
        // upgrades from monogram to photo when the map loads (nil → real URL re-fires this).
        .task(id: url) {
            guard let url else { image = nil; return }
            if let hit = ImageCache.shared.cached(url) {
                image = hit
                return
            }
            image = await ImageCache.shared.image(for: url)
        }
    }
}
