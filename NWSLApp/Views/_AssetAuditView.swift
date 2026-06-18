//
//  _AssetAuditView.swift
//  NWSLApp
//
//  TEMP (DEBUG-only) — the bundled-asset fidelity audit + the seed of the app's diagnostics
//  surface (NO SILENT FAILURES, principle #5). Renders every BUNDLED crest + featured flag at
//  a large size with a bundle/MISSING badge (so a fall-through is obvious, never silent), and
//  lists recent Diagnostics events. Shown in place of RootTabView when launched with
//  `-assetAudit`. Mirrors `_ColorAuditView`; will generalize into the proper diagnostics view.
//

#if DEBUG
import SwiftUI

struct AssetAuditView: View {
    // 11 vector + 5 raster (CHI/KC/BOS/DEN/GFC) crests.
    private let crests = ["LA","BAY","BOS","CHI","DEN","GFC","HOU","KC","NC","SEA","ORL","POR","LOU","SD","UTA","WAS"]
    // Featured national-team flags (the bundled set), keyed by FIFA code.
    private let flags = NationalTeam.featured.map(\.code)

    @State private var diagnostics = Diagnostics.shared

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                section("Crests (vector + raster)", names: crests.map { "Crests/\($0)" }, labels: crests)
                section("Flags · featured (vector)", names: flags.map { "Flags/\($0)" }, labels: flags)
                diagnosticsSection
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
                    let resolves = UIImage(named: name) != nil
                    VStack(spacing: 5) {
                        Image(name)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 96, height: 96)
                            .background(Color.white.opacity(0.04))
                        Text(label)
                            .font(.system(size: 10, weight: .medium).monospaced())
                            .foregroundStyle(Color.dsFgSecondary)
                        // The whole point of #4: a bundle miss must be loud, never silent.
                        Text(resolves ? "bundle" : "MISSING")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(resolves ? Color.green : Color.red)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 14)
    }

    // Live Diagnostics tail — the start of the generalized no-silent-failures surface.
    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Diagnostics (\(diagnostics.events.count))")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.dsFgPrimary)
            if diagnostics.events.isEmpty {
                Text("No events recorded this session.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.dsFgSecondary)
            } else {
                ForEach(diagnostics.events.prefix(40)) { event in
                    HStack(spacing: 6) {
                        Text(event.kind.rawValue)
                            .font(.system(size: 10, weight: .semibold).monospaced())
                            .foregroundStyle(Color.orange)
                        Text(event.detail)
                            .font(.system(size: 10).monospaced())
                            .foregroundStyle(Color.dsFgSecondary)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }
}
#endif
