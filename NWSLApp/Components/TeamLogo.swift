//
//  TeamLogo.swift
//  NWSLApp
//
//  Small team crest for match cards and (later) Standings / Team pages.
//  Wraps AsyncImage with a fixed frame, a loading placeholder, and a neutral
//  failure fallback so rows never reflow or show a broken-image glyph.
//
//  Extracted into Components/ on first use (MatchCard) because the same
//  logo + fallback behavior is needed by upcoming Standings and Team views —
//  one source of truth for size, placeholder, and accessibility.
//
//  Crests load through the shared in-memory ImageCache (NSCache singleton) rather
//  than a bare AsyncImage, so they aren't re-downloaded when a cell is recycled
//  during scroll. A synchronous cache hit paints on the first frame, so a
//  scrolled-back crest shows instantly with no flash.
//
//  FIRST-LAUNCH: the 16 NWSL crests are BUNDLED in the asset catalog (`Crests/<ABBR>`),
//  so a followed club's crest renders on the first frame with ZERO network — no cold-CDN
//  race on a fresh install (see Reference "First Launch Performance — Asset Strategy",
//  Tier 1). The bundled image is the default; the live proxy `/crest` + ESPN URLs are the
//  fallback only for non-NWSL sides (Champions Cup foreign clubs) that have no bundled
//  crest. A rebrand restamps via an app release (re-run the proxy `load_crests.mjs`); crests
//  change ~never, so trading background-refresh for a flawless cold start is the right call.
//

import SwiftUI

/// A team crest rendered at a fixed size. Falls back to a neutral rounded
/// placeholder (never a broken-image glyph) because the team abbreviation
/// shown beside it already identifies the club.
struct TeamLogo: View {
    let urlString: String?
    /// When set, the crisp NWSL crest (proxy `/crest?team=…`) is tried FIRST, with the ESPN
    /// `urlString` as the fallback if it isn't loaded (404) or fails. Nil keeps ESPN-only.
    var teamAbbreviation: String? = nil
    var size: CGFloat = 24

    // The decoded crest, once resolved. Seeded synchronously from the cache (see
    // body) so a cached image is shown on the first frame.
    @State private var image: UIImage?

    // The bundled crest for an NWSL club (asset-catalog `Crests/<ABBR>`), or nil for a
    // non-NWSL side or when no abbreviation is set. When present it renders on the first
    // frame with no network and the load task is skipped entirely.
    private var bundledCrest: UIImage? {
        guard let abbr = teamAbbreviation, !abbr.isEmpty else { return nil }
        return UIImage(named: "Crests/\(abbr.uppercased())")
    }

    // The preferred NWSL crest URL (nil when no abbreviation given).
    private var nwslURL: URL? {
        guard let abbr = teamAbbreviation, !abbr.isEmpty else { return nil }
        return AppConfig.crestURL(abbreviation: abbr)
    }

    // The ESPN crest URL (the fallback, and the only source when no abbreviation is set).
    // Guard nil/empty strings so an absent logo goes straight to the placeholder.
    private var espnURL: URL? {
        guard let urlString, !urlString.isEmpty else { return nil }
        return URL(string: urlString)
    }

    var body: some View {
        Group {
            if let bundledCrest {
                Image(uiImage: bundledCrest)         // bundled NWSL crest — instant, no network
                    .resizable()
                    .scaledToFit()
            } else if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                placeholder                         // loading / failure / nil URL
            }
        }
        .frame(width: size, height: size)           // fixed BEFORE load → no reflow
        .accessibilityHidden(true)                  // abbreviation already names the team
        // Keyed to both URLs so a recycled cell re-targets the right crest. Try the NWSL crest
        // first (synchronous cache hit → no flash, then fetch), then fall back to ESPN — both
        // through the shared ImageCache. Skipped entirely when a bundled crest is present.
        .task(id: taskID) {
            if bundledCrest != nil { return }       // bundled NWSL crest already renders; no fetch
            for candidate in [nwslURL, espnURL] {
                guard let candidate else { continue }
                if let hit = ImageCache.shared.cached(candidate) {
                    image = hit
                    return
                }
                if let fetched = await ImageCache.shared.image(for: candidate) {
                    image = fetched
                    return
                }
            }
            image = nil                             // both unavailable → neutral placeholder
        }
    }

    // A stable identity for the load task: re-runs only when the target crest changes.
    private var taskID: String { "\(nwslURL?.absoluteString ?? "")|\(espnURL?.absoluteString ?? "")" }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color(.tertiarySystemFill))
    }
}

#Preview {
    VStack(spacing: 12) {
        TeamLogo(urlString: "https://a.espncdn.com/i/teamlogos/soccer/500/example.png")
        TeamLogo(urlString: nil)            // fallback path
    }
    .padding()
}
