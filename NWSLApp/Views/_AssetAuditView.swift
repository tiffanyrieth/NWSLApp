//
//  _AssetAuditView.swift
//  NWSLApp
//
//  TEMP (DEBUG-only) — renders every BUNDLED crest + flag at a large size so the
//  vector (SVG, Preserve Vector Data) and raster assets can be scanned for fidelity
//  against the live raster. Shown in place of RootTabView when launched with
//  `-assetAudit`. Mirrors `_ColorAuditView`; remove once the bundled assets are
//  verified (see "First Launch Performance — Asset Strategy", Tier 1 fidelity pass).
//

#if DEBUG
import SwiftUI

struct AssetAuditView: View {
    // 11 vector + 5 raster (CHI/KC/BOS/DEN/GFC) crests.
    private let crests = ["LA","BAY","BOS","CHI","DEN","GFC","HOU","KC","NC","SEA","ORL","POR","LOU","SD","UTA","WAS"]
    // 16 national-team flags, keyed by FIFA code.
    private let flags  = ["USA","MEX","CAN","BRA","COL","ENG","JAM","JPN","AUS","FRA","GER","HAI","KOR","NGA","ESP","SWE"]

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                section("Crests (vector + raster)", names: crests.map { "Crests/\($0)" }, labels: crests)
                section("Flags (vector)", names: flags.map { "Flags/\($0)" }, labels: flags)
            }
            .background(Color.dsBgGrouped)
            .navigationTitle("Bundled Asset Audit")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }

    private func section(_ title: String, names: [String], labels: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.dsFgPrimary)
                .padding(.horizontal, 16)
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(Array(zip(names, labels)), id: \.0) { name, label in
                    VStack(spacing: 5) {
                        Image(name)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 96, height: 96)
                            .background(Color.white.opacity(0.04))
                        Text(label)
                            .font(.system(size: 10, weight: .medium).monospaced())
                            .foregroundStyle(Color.dsFgSecondary)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 14)
    }
}
#endif
