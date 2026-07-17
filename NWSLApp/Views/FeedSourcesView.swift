//
//  FeedSourcesView.swift
//  NWSLApp
//
//  The Feed tab's settings-gear sheet — content preferences. Two working,
//  persisted controls (backed by FeedPreferencesStore, shared with the Feed):
//   • SHOW IN FEED — toggle reporter posts / article links on or off.
//   • SOURCES — the reporters/outlets powering the Feed today, each with a switch
//     to hide (mute) it from the list.
//
//  Both filter the live Feed immediately. The sources list is derived from the
//  actual Feed items (FeedViewModel.sources()), so muting maps exactly to what's
//  shown. ("Add your own source" needs a real content backend — the Feed runs on
//  a TEMP curated seed today — so it isn't offered; see CLAUDE.md What's-Next.)
//

import SwiftUI

struct FeedSourcesView: View {
    /// The distinct sources powering the Feed, passed in from FeedViewModel.
    let sources: [FeedViewModel.Source]

    @Environment(\.dismiss) private var dismiss
    @Environment(FeedPreferencesStore.self) private var preferences

    var body: some View {
        @Bindable var prefs = preferences
        // The default chip is persisted as a raw string; bridge it to the picker's
        // ContentFilter so the store stays free of a view-model dependency.
        let defaultFilter = Binding<FeedViewModel.ContentFilter>(
            get: { FeedViewModel.ContentFilter(rawValue: prefs.defaultFeedFilter) ?? .all },
            set: { prefs.defaultFeedFilter = $0.rawValue }
        )
        return NavigationStack {
            List {
                Section {
                    Picker("Open Feed to", selection: defaultFilter) {
                        ForEach(FeedViewModel.ContentFilter.allCases, id: \.self) { filter in
                            Text(filter.label).tag(filter)
                        }
                    }
                } header: {
                    Text("Default view")
                } footer: {
                    Text("The chip your Feed opens to.")
                }

                Section {
                    Toggle("Reporter posts", isOn: $prefs.showReporterPosts)
                    Toggle("Article links", isOn: $prefs.showArticleLinks)
                } header: {
                    Text("Show in feed")
                } footer: {
                    Text("Choose which kinds of content appear in your Feed.")
                }

                Section {
                    ForEach(sources) { source in
                        sourceRow(source, prefs: prefs)
                    }
                } header: {
                    Text("Sources")
                } footer: {
                    Text("These NWSL reporters and outlets power your Feed. Turn one off to hide it.")
                }
            }
            .navigationTitle("Content preferences")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func sourceRow(_ source: FeedViewModel.Source, prefs: FeedPreferencesStore) -> some View {
        // The toggle reads as "shown": on = visible, off = muted. Bridges to the
        // store's muted set (the inverse) so persistence stays the source of truth.
        let shown = Binding(
            get: { !prefs.isMuted(source.name) },
            set: { prefs.setMuted(source.name, !$0) }
        )
        return Toggle(isOn: shown) {
            VStack(alignment: .leading, spacing: 2) {
                Text(source.name)
                    .dsFont(15, weight: .semibold)
                Text(source.detail)
                    .dsFont(12)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    FeedSourcesView(sources: [
        FeedViewModel.Source(name: "The Athletic", detail: "The Athletic"),
        FeedViewModel.Source(name: "Meg Linehan", detail: "@meglinehan"),
    ])
    .environment(FeedPreferencesStore())
}
