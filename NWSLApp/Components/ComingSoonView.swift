//
//  ComingSoonView.swift
//  NWSLApp
//
//  Intentional placeholder for a tab/section that exists in the navigation
//  structure but isn't built yet. This is NOT a blank or broken screen — it
//  names the destination and tells the user it's on the way, satisfying the
//  "placeholder sections must look intentional" rule (see CLAUDE.md). When a
//  real screen lands, its tab in RootTabView simply stops pointing here.
//
//  Reusable on purpose: one component drives all four not-yet-built tabs
//  (Home, Standings, Teams, Feed) instead of four near-identical stub files.
//

import SwiftUI

struct ComingSoonView: View {
    /// The destination's name, shown as the nav title and in the message.
    let title: String
    /// SF Symbol that matches the tab's icon, so the placeholder reads as the
    /// same destination the user just tapped.
    let systemImage: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.secondary)
            Text("\(title) is coming soon")
                .font(.headline)
            Text("We're building this out — check back as the app grows.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(title)
    }
}

#Preview {
    NavigationStack {
        ComingSoonView(title: "Home", systemImage: "house")
    }
}
