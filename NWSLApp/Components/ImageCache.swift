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
//  TWO tiers: a decoded-image `NSCache` (in-memory, in-session speed; evicts under
//  pressure, gone on termination) over a disk `URLCache` on a DEDICATED image session, so
//  remote images (browse-all flags, headshots, feed/video thumbnails) persist across cold
//  launches instead of re-downloading every launch. The disk layer is HTTP-revalidating
//  (`.useProtocolCachePolicy`) — fresh-from-disk within the response's freshness window,
//  conditional-GET when stale — so it's never stale (Tier 2 of the first-launch asset
//  strategy). NB: Caches is wiped on app DELETE, so this survives cold launches, not
//  reinstalls — only the bundled assets survive a reinstall.
//
//  The disk cache is ISOLATED to images (its own `URLCache` on `session`), deliberately NOT
//  the global `URLCache.shared` — the live API/proxy JSON (scoreboard/feed/spotlight) must
//  stay fresh per the online-only model and keeps using `URLSession.shared` untouched.
//

import UIKit
import ImageIO

final class ImageCache {
    static let shared = ImageCache()

    // NSCache is already thread-safe, so no extra locking is needed.
    private let cache = NSCache<NSString, UIImage>()

    // Dedicated session whose URLCache persists image bytes to disk across launches,
    // revalidating per HTTP headers. Separate from URLSession.shared so API freshness is untouched.
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(
            // Small memory window on purpose: the decoded-image `NSCache` above is the real
            // in-session layer, so we keep URLCache's RAW-bytes memory tiny to push responses to
            // DISK promptly — that's what survives a cold launch (a large memory window would let
            // small images linger in RAM and never persist before termination).
            memoryCapacity: 2 * 1024 * 1024,    // 2 MB raw-bytes memory
            diskCapacity: 200 * 1024 * 1024,    // 200 MB on disk (LRU-evicted by the system)
            directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ImageURLCache", isDirectory: true)
        )
        config.requestCachePolicy = .useProtocolCachePolicy  // serve fresh-from-disk, revalidate when stale
        session = URLSession(configuration: config)
    }

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
            // Goes through the dedicated image session → disk URLCache (revalidating) before
            // the network, so a cold-launch fetch is usually a fast local read, not a download.
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                return nil
            }
            guard let image = Self.downsampledImage(data: data, maxPixel: 1000) else {
                // 2xx but the bytes aren't an image — genuinely unexpected (a non-2xx/404, e.g. a
                // headshot miss, took the branch above and stays silent: that's an expected fallback).
                let host = url.host ?? ""
                Task { @MainActor in Diagnostics.shared.record(.parseError, "image decode \(host)") }
                return nil
            }
            cache.setObject(image, forKey: url.absoluteString as NSString)
            return image
        } catch {
            let host = url.host ?? ""
            Task { @MainActor in Diagnostics.shared.record(.apiFailure, "image fetch \(host)") }
            return nil
        }
    }

    /// Decode + DOWNSAMPLE via ImageIO so a large CDN source (IG / YouTube / news OG, often 1080px+)
    /// becomes a ~card-sized bitmap instead of a full-res one held in the NSCache and force-decoded on the
    /// MAIN thread at draw time (the feed / club-news scroll cost). Downsampling only SHRINKS — a source
    /// already ≤ maxPixel (crests, headshots) comes back effectively unchanged, and the largest consumer is
    /// a ~200pt card (≈600px @3x), so 1000px stays crisp. Runs in the async `image(for:)` context, so the
    /// decode is off the main thread. Falls back to a plain decode if ImageIO can't read the bytes.
    private static func downsampledImage(data: Data, maxPixel: Int) -> UIImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData,
                                                    [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return UIImage(data: data)
        }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // respect EXIF orientation
            kCGImageSourceShouldCacheImmediately: true,          // decode NOW (off-main), not at draw time
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cg)
    }
}
