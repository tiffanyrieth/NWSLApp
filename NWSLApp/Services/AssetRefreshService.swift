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

        // Crests: a changed hash → re-download the proxy /crest PNG as the override.
        for (abbr, remoteHash) in manifest.crests {
            let key = "crest_\(abbr.uppercased())"
            let effective = overrides[key] ?? BundledAssetManifest.crests[abbr.uppercased()]
            guard remoteHash != effective, let src = AppConfig.crestURL(abbreviation: abbr) else { continue }
            if await download(src, to: key) { overrides[key] = remoteHash; markDownloaded(key) }
        }

        // Flags: a changed hash → re-download a high-res flagcdn raster as the override.
        for (code, remoteHash) in manifest.flags {
            let key = "flag_\(code.uppercased())"
            let effective = overrides[key] ?? BundledAssetManifest.flags[code.uppercased()]
            guard remoteHash != effective,
                  let slug = NationalTeam.team(code: code.uppercased())?.flagSlug,
                  let src = AppConfig.flagRasterURL(slug: slug) else { continue }
            if await download(src, to: key) { overrides[key] = remoteHash; markDownloaded(key) }
        }

        defaults.set(overrides, forKey: overridesKey)
    }

    /// Make a freshly-downloaded override visible to the in-memory lookup (the new file would
    /// otherwise be missed until next launch's dir scan, and a stale decode could linger).
    private static func markDownloaded(_ key: String) {
        existingKeys?.insert(key)
        decoded[key] = nil
    }

    // MARK: - Networking + disk (all best-effort)

    private struct Manifest: Decodable {
        let crests: [String: String]
        let flags: [String: String]
    }

    private static func fetchManifest(_ url: URL) async -> Manifest? {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(Manifest.self, from: data)
    }

    /// Download `url` and write it atomically to `<name>.png` in the cache dir. Returns whether
    /// the bytes were a decodable image (so a 404/HTML error page never overwrites a good file).
    private static func download(_ url: URL, to name: String) async -> Bool {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              UIImage(data: data) != nil else { return false }
        let dest = cacheDir.appendingPathComponent("\(name).png")
        return (try? data.write(to: dest, options: .atomic)) != nil
    }

    private static let cacheDir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("AssetOverrides", isDirectory: true)
    }()

    private static func ensureCacheDir() {
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }
}
