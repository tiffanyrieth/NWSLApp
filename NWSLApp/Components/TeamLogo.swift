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
//  FIRST-LAUNCH: the 16 NWSL crests (`Crests/<ABBR>`) and 16 national-team flags
//  (`Flags/<FIFA>`) are BUNDLED in the asset catalog as resolution-independent VECTOR
//  assets, so a followed side's mark renders on the first frame with ZERO network — no
//  cold-CDN race on a fresh install (see Reference "First Launch Performance — Asset
//  Strategy", Tier 1). The bundled image is the default; the live proxy `/crest` + ESPN
//  URLs are the fallback only for non-NWSL, non-national sides (Champions Cup foreign clubs)
//  that have no bundled mark. A rebrand is picked up out-of-band by the cadenced crest/flag
//  refresh (cache overrides the bundle), so a cold start never blocks on it.
//

import SwiftUI
import OSLog

/// A team crest rendered at a fixed size. Falls back to a neutral rounded
/// placeholder (never a broken-image glyph) because the team abbreviation
/// shown beside it already identifies the club.
struct TeamLogo: View {
    let urlString: String?
    /// When set, the crisp NWSL crest (proxy `/crest?team=…`) is tried FIRST, with the ESPN
    /// `urlString` as the fallback if it isn't loaded (404) or fails. Nil keeps ESPN-only.
    let teamAbbreviation: String?

    // The rendered crest size at the DEFAULT text setting, scaled with Dynamic Type (capped
    // at the root — see RootTabView). The crest is HERO content, not a fixed icon: it grows/
    // shrinks WITH the paired abbreviation. Scaled relative to `.body` — the same axis `dsFont`
    // uses — so crest + text move in lockstep. Size still locks per layout pass before the async
    // load, so the "no reflow on image arrival" guarantee holds.
    @ScaledMetric private var size: CGFloat

    init(urlString: String?, teamAbbreviation: String? = nil, size: CGFloat = 24,
         relativeTo: Font.TextStyle = .body) {
        self.urlString = urlString
        self.teamAbbreviation = teamAbbreviation
        _size = ScaledMetric(wrappedValue: size, relativeTo: relativeTo)
    }

    // The decoded crest, once resolved. Seeded synchronously from the cache (see
    // body) so a cached image is shown on the first frame.
    @State private var image: UIImage?

    // The bundled mark for this side, rendered on the first frame with ZERO network (the
    // load task is then skipped). Resolves an NWSL club crest (`Crests/<ABBR>`) first, then a
    // women's national-team flag (`Flags/<FIFA>`) — national-team competitors carry their FIFA
    // code as the abbreviation, so a USA/MEX/… side gets its bundled flag on the Schedule cards
    // too. nil for a non-NWSL, non-national side (e.g. a Champions Cup foreign club) → network.
    private var bundledMark: UIImage? {
        guard let abbr = teamAbbreviation, !abbr.isEmpty else { return nil }
        let key = abbr.uppercased()
        // A cached post-rebrand override (if the refresh downloaded one) wins over the
        // bundled vector; then the asset catalog. nil → network (non-NWSL/non-national side).
        return AssetRefreshService.override(crest: key)
            ?? AssetRefreshService.override(flag: key)
            ?? UIImage(named: "Crests/\(key)")
            ?? UIImage(named: "Flags/\(key)")
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
            if let bundledMark {
                Image(uiImage: bundledMark)          // bundled crest / flag — instant, no network
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
            if bundledMark != nil {                  // bundled crest/flag already renders; no fetch
                #if DEBUG
                let source = (teamAbbreviation.flatMap { AssetRefreshService.override(crest: $0) ?? AssetRefreshService.override(flag: $0) } != nil) ? "cache-override" : "bundle"
                Self.log.debug("TeamLogo \(teamAbbreviation ?? "—", privacy: .public) → \(source, privacy: .public)")
                #endif
                return
            }
            // About to hit the network. If this mark was SUPPOSED to be bundled (an NWSL club or a
            // featured national team), a bundled asset has silently fallen through — record it
            // loudly (no silent failures) so a missing/broken bundle is caught in the field.
            if let abbr = teamAbbreviation, !abbr.isEmpty, Self.expectedBundled(abbr) {
                Diagnostics.shared.record(.assetBundleMiss, abbr.uppercased())
            }
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

    #if DEBUG
    private static let log = Logger(subsystem: "com.tiffanyrieth.nwslapp", category: "TeamLogo")
    #endif

    // Should this abbreviation resolve from the bundle? True for an NWSL club (the membership
    // test) or a featured national team — exactly the marks we bundle. A non-NWSL foreign club
    // legitimately has no bundle and is expected to hit the network (not a miss).
    private static func expectedBundled(_ abbreviation: String) -> Bool {
        let key = abbreviation.uppercased()
        return DesignTeamColors.hex(for: key) != nil || BundledAssetManifest.flags[key] != nil
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.dsBgTertiary)
    }
}

#Preview {
    VStack(spacing: 12) {
        TeamLogo(urlString: "https://a.espncdn.com/i/teamlogos/soccer/500/example.png")
        TeamLogo(urlString: nil)            // fallback path
    }
    .padding()
}
