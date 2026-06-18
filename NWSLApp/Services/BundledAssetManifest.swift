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

    /// National-team FIFA code → source-master hash.
    static let flags: [String: String] = [
        "USA": "e1792c011daad918", "MEX": "baa6f7163f307c16", "CAN": "3cd6c2b9fe12bc06",
        "BRA": "e0215eff9f53b023", "COL": "ec3daa5a284fc6d1", "ENG": "cc76327923f60bb6",
        "JAM": "44504dda9d5bff31", "JPN": "e8e6f6e75bc02eeb", "AUS": "b826e039804d5cf3",
        "FRA": "09645c97a4743633", "GER": "595d7718f6a22e5e", "HAI": "65839463e163fd81",
        "KOR": "4e0b6d5fa63e2fc1", "NGA": "3dbebd9f8e31821d", "ESP": "d672868d51fc5b4f",
        "SWE": "426348d99d9cace2",
    ]
}
