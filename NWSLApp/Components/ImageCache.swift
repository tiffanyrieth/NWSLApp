//
//  ImageCache.swift
//  NWSLApp
//
//  A tiny in-memory image cache shared app-wide, used by TeamLogo so team crests
//  aren't re-downloaded every time a card is recycled during scroll (the
//  full-season schedule recycles the same ~16 crests constantly).
//
//  TEMP/architecture (deliberate exception): this is a `static let shared`
//  singleton rather than an injected dependency. TeamLogo has ~15 call sites,
//  many in leaf components (MatchCard, PlayerCard, ComingUpRow) that aren't in
//  the environment, so threading an injected cache through all of them is heavy
//  for a 16-image cache. A singleton is the idiomatic shape for an image cache
//  and keeps TeamLogo's init unchanged. Swap for a shared loader / the proxy if
//  caching ever needs to be configurable (see CLAUDE.md What's-Next #1).
//
//  In-memory only — `NSCache` evicts under memory pressure and the cache is gone
//  on app termination. That's fine for 16 small PNGs; disk caching is overkill.
//

import UIKit

final class ImageCache {
    static let shared = ImageCache()

    // NSCache is already thread-safe, so no extra locking is needed.
    private let cache = NSCache<NSString, UIImage>()

    private init() {}

    /// A synchronous cache hit, if present — lets TeamLogo paint a cached crest on
    /// the first frame (no flash/reflow when a scrolled cell is recycled).
    func cached(_ url: URL) -> UIImage? {
        cache.object(forKey: url.absoluteString as NSString)
    }

    /// Returns the cached image or fetches, decodes, and caches it. Returns nil on
    /// any failure (bad status, decode error, network) so TeamLogo falls back to
    /// its neutral placeholder rather than a broken-image glyph.
    func image(for url: URL) async -> UIImage? {
        if let hit = cached(url) { return hit }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                return nil
            }
            guard let image = UIImage(data: data) else { return nil }
            cache.setObject(image, forKey: url.absoluteString as NSString)
            return image
        } catch {
            return nil
        }
    }
}
