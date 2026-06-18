//
//  BundledAssetManifest.swift
//  NWSLApp
//
//  The version hash of every crest + flag SHIPPED in this build, used by
//  AssetRefreshService to detect a rebrand against the proxy's `/crest/manifest`
//  without re-downloading anything that hasn't changed.
//
//  Each hash is the sha256 (first 16 hex) of the asset's SOURCE MASTER — the raw NWSL
//  crest SVG/PNG and the raw flagcdn flag SVG — NOT the bundled (vector) encoding. The
//  proxy hashes the same masters, so a freshly-installed app's bundled hashes equal the
//  proxy's manifest and nothing re-downloads; they only diverge when NWSL/flagcdn changes
//  a master (a rebrand), which is exactly when we want the cached override to kick in.
//
//  GENERATED — when the bundled crest/flag assets change, regenerate these to match the
//  exact source bytes that were bundled (see `scripts/build_asset_manifest.mjs` in the
//  proxy repo, which writes the proxy side from the same masters).
//

import Foundation

enum BundledAssetManifest {
    /// Crest abbreviation → source-master hash.
    static let crests: [String: String] = [
        "LA": "7ab782fc79a6beb1", "BAY": "203fbbe66aaf3969", "BOS": "a0b54d893a12d603",
        "CHI": "3d6555e08948e3e0", "DEN": "477bde1fb14d5e80", "GFC": "5e40b41b64760821",
        "HOU": "f067191e4d0e7d5b", "KC": "feef561500e88e9b", "NC": "0b0b8ce0683cc66b",
        "SEA": "5cc45476847d9895", "ORL": "2ade228799a8a935", "POR": "d1c6030522099889",
        "LOU": "cc61758ed3c82ed6", "SD": "09c0136472026ef1", "UTA": "4a739abe363b9db1",
        "WAS": "5d7df7ae77729556",
    ]

    /// National-team FIFA code → source-master hash. The FEATURED set only (the ~8 shown before
    /// "Browse all") is bundled; the growing browse-all list is download-and-cache, not bundled,
    /// so the country list isn't chained to app releases (rule: bundle = featured, browse-all =
    /// download + cache).
    static let flags: [String: String] = [
        "USA": "e1792c011daad918", "MEX": "baa6f7163f307c16", "CAN": "3cd6c2b9fe12bc06",
        "BRA": "e0215eff9f53b023", "COL": "ec3daa5a284fc6d1", "ENG": "cc76327923f60bb6",
        "JAM": "44504dda9d5bff31", "JPN": "e8e6f6e75bc02eeb",
    ]

    /// The crests with NO vector master (CHI/KC/BOS/DEN/GFC) — bundled as raster PNG. Every other
    /// bundled crest, and every bundled flag, is vector. Used by AssetRefreshService to enforce
    /// the no-downgrade rule: a vector-bundled asset is never replaced by a downloaded raster
    /// override unless the NEW master is itself raster-only.
    static let rasterCrests: Set<String> = ["CHI", "KC", "BOS", "DEN", "GFC"]

    /// Is the bundled crest for this abbreviation a vector asset (so a raster override would be a
    /// downgrade)? False for the 5 raster-only teams and for anything not bundled.
    static func isVectorCrest(_ abbreviation: String) -> Bool {
        let key = abbreviation.uppercased()
        return crests[key] != nil && !rasterCrests.contains(key)
    }
}
