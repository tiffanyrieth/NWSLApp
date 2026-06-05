//
//  FeedSourcesView.swift
//  NWSLApp
//
//  The Feed tab's settings-gear sheet — "reserves the spot for source
//  management" (design spec). It shows the curated default sources the Feed
//  pulls from today and marks the not-yet-built management actions (add your own
//  accounts, mute sources, content-mix preferences) as intentional placeholders.
//
//  INTENTIONAL PLACEHOLDER: the rows are read-only and "Add a source" is disabled
//  because there's no content backend yet (the Feed runs on a TEMP curated seed —
//  see FeedContentProvider). When a real source pipeline lands, this becomes the
//  live source manager. It looks deliberate, not forgotten, per the UI rules.
//

import SwiftUI

struct FeedSourcesView: View {
    @Environment(\.dismiss) private var dismiss

    /// The curated reporters/outlets the seed currently draws from. Keeps this
    /// screen honest about what's powering the Feed today.
    private let defaultSources: [(name: String, detail: String, symbol: String)] = [
        ("The Athletic", "NWSL beat coverage", "newspaper.fill"),
        ("ESPN", "NWSL news & analysis", "newspaper.fill"),
        ("The Equalizer", "Women's soccer coverage", "newspaper.fill"),
        ("Just Women's Sports", "Women's sports news", "newspaper.fill"),
        ("Meg Linehan", "@meglinehan · The Athletic", "at"),
        ("Jeff Kassouf", "@jeffkassouf · ESPN / The Equalizer", "at"),
        ("Steph Yang", "@stephyang · The Athletic", "at"),
        ("Sandra Herrera", "@sandraherrera · CBS Sports", "at"),
        ("Jenna Tonelli", "@jennatonelli · Sports Illustrated", "at"),
        ("Claire Watkins", "@clairewatkins · Just Women's Sports", "at"),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(defaultSources, id: \.name) { source in
                        HStack(spacing: 12) {
                            Image(systemName: source.symbol)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(source.symbol == "at" ? Color.blue : Color.secondary)
                                .clipShape(Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.name)
                                    .font(.subheadline.weight(.semibold))
                                Text(source.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("Curated sources")
                } footer: {
                    Text("These NWSL reporters and outlets power your Feed today.")
                }

                Section {
                    Label("Add a source", systemImage: "plus.circle")
                        .foregroundStyle(.secondary)
                    Label("Content preferences", systemImage: "slider.horizontal.3")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Coming soon")
                } footer: {
                    Text("Soon you'll be able to add your own reporter accounts, mute sources, and tune the mix of posts vs. articles.")
                }
            }
            .navigationTitle("Sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    FeedSourcesView()
}
