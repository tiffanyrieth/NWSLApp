//
//  _ColorAuditView.swift
//  NWSLApp
//
//  TEMP (DEBUG-only) — a one-screen audit of all 16 clubs' resolved team colors, so
//  the primary/secondary swatches can be scanned at a glance against each club's
//  official brand colors to catch mis-keyed/swapped entries. Shown in place of
//  RootTabView when launched with `-colorAudit`. Remove once the palette is verified.
//

#if DEBUG
import SwiftUI

struct ColorAuditView: View {
    @State private var store = ClubStore()

    private var clubs: [Club] {
        store.clubs.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(clubs) { row($0) }
                }
            }
            .background(Color.dsBgGrouped)
            .navigationTitle("Team Color Audit")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
        .task { if case .idle = store.state { await store.load() } }
    }

    private func row(_ club: Club) -> some View {
        HStack(spacing: 10) {
            TeamLogo(urlString: club.logoURL, teamAbbreviation: club.abbreviation, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(club.displayName)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.dsFgPrimary)
                    .lineLimit(1)
                Text(club.abbreviation)
                    .font(.system(size: 10, weight: .medium).monospaced())
                    .foregroundStyle(Color.dsFgSecondary)
            }
            Spacer(minLength: 4)
            swatch(color: club.accentColor, hex: club.brandHex)
            swatch(color: club.brandAltHex.map { Color(hex: $0) }, hex: club.brandAltHex)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.dsSeparator).frame(height: 0.5)
        }
    }

    @ViewBuilder
    private func swatch(color: Color?, hex: String?) -> some View {
        VStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 5)
                .fill(color ?? .clear)
                .frame(width: 50, height: 24)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.12), lineWidth: 0.5))
            Text(hex.map { "#\($0)" } ?? "—")
                .font(.system(size: 8.5, weight: .medium).monospaced())
                .foregroundStyle(Color.dsFgSecondary)
        }
        .frame(width: 56)
    }
}
#endif
