//
//  AssetRefreshService.swift
//  NWSLApp
//
//  Out-of-band refresh for the BUNDLED crest + flag artwork, so a mid-season rebrand
//  shows up WITHOUT an app release — while a cold start never blocks or slows on it.
//
//  How it stays off the cold-start path:
//   • The bundled vector asset always renders on the first frame (TeamLogo / NationalTeamCard
//     read it synchronously). This service never gates that.
//   • It runs on a CADENCE, not every launch: only when >30 days since the last check, and
//     forced once at season start (March, when rebrands land). The check fetches one small
//     JSON manifest — not 16 images.
//   • On a hash mismatch it downloads ONLY the changed asset into the Caches dir and records
//     it. The override is picked up on the NEXT launch (the views' synchronous override read),
//     so nothing reflows mid-session and the work is fully background + best-effort.
//
//  Resolution order in the views: cached override (post-rebrand) → bundled asset → network.
//  The manifest hashes the SOURCE MASTER (see BundledAssetManifest), so a fresh install's
//  bundled hashes equal the proxy's and nothing downloads until a master actually changes.
//

import UIKit

@MainActor
enum AssetRefreshService {
    // MARK: - Synchronous override lookup (called from view bodies; no network, no async)

    /// A downloaded post-rebrand crest override (raster PNG), or nil to fall through to the
    /// bundled vector. Keyed by team abbreviation.
    static func override(crest abbreviation: String) -> UIImage? {
        cachedImage("crest_\(abbreviation.uppercased())")
    }

    /// A downloaded post-rebrand flag override (raster PNG), or nil to fall through to the
    /// bundled vector. Keyed by FIFA code.
    static func override(flag code: String) -> UIImage? {
        cachedImage("flag_\(code.uppercased())")
    }

    // In-memory caches so the common case (no override exists) costs a single Set lookup, not
    // a disk syscall on every TeamLogo body eval during scroll. `existingKeys` is the set of
    // override basenames on disk, scanned once; `decoded` memoizes the loaded images.
    private static var existingKeys: Set<String>?
    private static var decoded: [String: UIImage] = [:]

    private static func cachedImage(_ name: String) -> UIImage? {
        if existingKeys == nil { existingKeys = scanExistingKeys() }
        guard existingKeys?.contains(name) == true else { return nil }
        if let memo = decoded[name] { return memo }
        let image = UIImage(contentsOfFile: cacheDir.appendingPathComponent("\(name).png").path)
        decoded[name] = image
        return image
    }

    private static func scanExistingKeys() -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: cacheDir.path)) ?? []
        return Set(names.filter { $0.hasSuffix(".png") }.map { String($0.dropLast(4)) })
    }

    // MARK: - Cadenced refresh (kicked off in the background from RootTabView)

    private static let lastCheckKey = "asset.refresh.lastCheck"      // Date (epoch seconds)
    private static let marchYearKey = "asset.refresh.marchForceYear" // Int (year already forced)
    private static let overridesKey = "asset.refresh.overrideHashes" // [assetKey: hash] downloaded

    /// Run the refresh if the cadence is due, else return immediately. Best-effort: every
    /// failure is swallowed so the bundled assets simply stand.
    static func refreshIfDue() async {
        guard isDue() else { return }
        await refresh()
    }

    private static func isDue() -> Bool {
        let defaults = UserDefaults.standard
        let now = Date()
        let last = defaults.double(forKey: lastCheckKey) // 0 = never checked
        let over30Days = (now.timeIntervalSince1970 - last) > 30 * 24 * 60 * 60

        let cal = Calendar.current
        let month = cal.component(.month, from: now)
        let year = cal.component(.year, from: now)
        let marchNotYetForced = (month == 3) && (defaults.integer(forKey: marchYearKey) != year)

        return last == 0 || over30Days || marchNotYetForced
    }

    private static func refresh() async {
        // Stamp the check up front so a hang/failure doesn't re-fire every launch.
        let defaults = UserDefaults.standard
        let now = Date()
        defaults.set(now.timeIntervalSince1970, forKey: lastCheckKey)
        if Calendar.current.component(.month, from: now) == 3 {
            defaults.set(Calendar.current.component(.year, from: now), forKey: marchYearKey)
        }

        guard let url = AppConfig.assetManifestURL(),
              let manifest = await fetchManifest(url) else { return }

        ensureCacheDir()
        var overrides = (defaults.dictionary(forKey: overridesKey) as? [String: String]) ?? [:]

        // Crests: a changed hash → re-download the proxy /crest PNG as the override — but a
        // vector-bundled crest is now SHARPER than that raster, so we don't downgrade it unless
        // the new brand is itself raster-only (see noDowngradeBlocks).
        for (abbr, entry) in manifest.crests {
            let key = "crest_\(abbr.uppercased())"
            let effective = overrides[key] ?? BundledAssetManifest.crests[abbr.uppercased()]
            guard entry.h != effective else { continue }                      // unchanged
            if noDowngradeBlocks(bundledVector: BundledAssetManifest.isVectorCrest(abbr),
                                 newMasterIsVector: entry.v, asset: "crest:\(abbr)") { continue }
            guard let src = AppConfig.crestURL(abbreviation: abbr) else { continue }
            if await download(src, to: key) {
                overrides[key] = entry.h; markDownloaded(key)
                Diagnostics.shared.record(.assetOverrideApplied, "crest:\(abbr)")
            }
        }

        // Flags: every BUNDLED flag is vector, and flagcdn only ever serves vector, so this
        // effectively never overrides — a flag rebrand rides the next app re-bundle rather than
        // downgrading to a raster. The branch stays general for the (theoretical) raster-only case.
        for (code, entry) in manifest.flags {
            let key = "flag_\(code.uppercased())"
            let effective = overrides[key] ?? BundledAssetManifest.flags[code.uppercased()]
            guard entry.h != effective else { continue }                      // unchanged
            let bundledVector = BundledAssetManifest.flags[code.uppercased()] != nil // bundled flags are vector
            if noDowngradeBlocks(bundledVector: bundledVector, newMasterIsVector: entry.v,
                                 asset: "flag:\(code)") { continue }
            guard let slug = NationalTeam.team(code: code.uppercased())?.flagSlug,
                  let src = AppConfig.flagRasterURL(slug: slug) else { continue }
            if await download(src, to: key) {
                overrides[key] = entry.h; markDownloaded(key)
                Diagnostics.shared.record(.assetOverrideApplied, "flag:\(code)")
            }
        }

        defaults.set(overrides, forKey: overridesKey)
    }

    /// True when applying a raster cache-override would DOWNGRADE a sharper vector-bundled asset.
    /// A downloaded override is always a raster (SwiftUI can't draw an SVG from disk), so when the
    /// bundle is vector AND the new master is also vector, the right fix is a vector re-bundle at
    /// the next app release — not a raster swap. We skip the override and record it loudly so the
    /// pending rebrand is visible, never silent. (Bundle-raster or a genuinely raster-only new
    /// master → overriding is no downgrade, so it proceeds.)
    private static func noDowngradeBlocks(bundledVector: Bool, newMasterIsVector: Bool, asset: String) -> Bool {
        guard bundledVector && newMasterIsVector else { return false }
        Diagnostics.shared.record(.assetVectorRebrandPending, asset)
        return true
    }

    /// Make a freshly-downloaded override visible to the in-memory lookup (the new file would
    /// otherwise be missed until next launch's dir scan, and a stale decode could linger).
    private static func markDownloaded(_ key: String) {
        existingKeys?.insert(key)
        decoded[key] = nil
    }

    // MARK: - Networking + disk (all best-effort)

    /// One manifest entry: `h` = source-master hash (matches BundledAssetManifest), `v` = whether
    /// that master is vector (an SVG) — drives the no-downgrade rule.
    private struct Entry: Decodable {
        let h: String
        let v: Bool
    }
    private struct Manifest: Decodable {
        let crests: [String: Entry]
        let flags: [String: Entry]
    }

    private static func fetchManifest(_ url: URL) async -> Manifest? {
        let data: Data
        do {
            let (d, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                // Refresh silently does nothing on a bad manifest; flag a real CDN/proxy outage.
                Diagnostics.shared.record(.apiFailure, "asset manifest: HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return nil
            }
            data = d
        } catch {
            Diagnostics.shared.record(.apiFailure, "asset manifest fetch: \(error.localizedDescription)")
            return nil
        }
        do {
            return try JSONDecoder().decode(Manifest.self, from: data)
        } catch {
            Diagnostics.shared.record(.parseError, "asset manifest decode: \(error.localizedDescription)")
            return nil
        }
    }

    /// Download `url` and write it atomically to `<name>.png` in the cache dir. Returns whether
    /// the bytes were a decodable image (so a 404/HTML error page never overwrites a good file).
    private static func download(_ url: URL, to name: String) async -> Bool {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200, UIImage(data: data) != nil else {
                Diagnostics.shared.record(.apiFailure, "asset download \(name): bad response / non-image")
                return false
            }
            let dest = cacheDir.appendingPathComponent("\(name).png")
            do {
                try data.write(to: dest, options: .atomic)
                return true
            } catch {
                Diagnostics.shared.record(.apiFailure, "asset write \(name): \(error.localizedDescription)")
                return false
            }
        } catch {
            Diagnostics.shared.record(.apiFailure, "asset download \(name): \(error.localizedDescription)")
            return false
        }
    }

    private static let cacheDir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("AssetOverrides", isDirectory: true)
    }()

    private static func ensureCacheDir() {
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }
}
