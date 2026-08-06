//
//  FeedSourcesView.swift
//  NWSLApp
//
//  The Social tab's settings-gear sheet — content preferences. Sections:
//   • DEFAULT VIEW — which chip the Feed opens to.
//   • SHOW IN FEED — reporter posts / article links on or off.
//   • ADD A REPORTER (Phase 3) — search a Bluesky handle, validate it has recent NWSL
//     posts, and add it; added handles join the Feed + the Sources list (ADDED badge).
//   • FOLLOW PLAYERS (Phase 3) — your teams' players inline (on by default), plus
//     "Browse all" → PlayerBrowseView to follow national-team stars beyond your teams.
//   • SOURCES — the reporters/outlets in the Feed, each with a mute switch.
//
//  All state is device-local via FeedPreferencesStore (user CHOICES don't restore across
//  reinstall — THE RESTORE LINE). The player directory + handle validation come from the
//  proxy (ContentService); the app stays thin.
//

import SwiftUI

struct FeedSourcesView: View {
    /// The distinct sources powering the Feed (incl. user-added reporters, flagged `isAdded`).
    let sources: [FeedViewModel.Source]
    /// The user's followed-club abbreviations — scopes the inline "your teams" player list.
    let followedTeamAbbrs: [String]
    /// Abbreviation → full club name, for the player-section team headers.
    let teamNames: [String: String]

    @Environment(\.dismiss) private var dismiss
    @Environment(FeedPreferencesStore.self) private var preferences

    @State private var players: [FeedPlayer] = []
    @State private var didLoadPlayers = false
    private let content = ContentService()

    // Add-a-reporter search
    @State private var searchText = ""
    @State private var searchState: ReporterSearch = .idle

    enum ReporterSearch: Equatable {
        case idle, loading, notFound, failed
        case found(handle: String, displayName: String)
    }

    var body: some View {
        @Bindable var prefs = preferences
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
                } header: { Text("Default view") } footer: { Text("The chip your Feed opens to.") }

                Section {
                    Toggle("Reporter posts", isOn: $prefs.showReporterPosts)
                    Toggle("Article links", isOn: $prefs.showArticleLinks)
                } header: { Text("Show in feed") } footer: {
                    Text("Choose which kinds of content appear in your Feed.")
                }

                addReporterSection(prefs: prefs)
                followPlayersSection(prefs: prefs)

                Section {
                    ForEach(sources) { source in sourceRow(source, prefs: prefs) }
                } header: { Text("Sources") } footer: {
                    Text("The reporters and outlets powering your Feed. Turn one off to hide it.")
                }
            }
            .navigationTitle("Content preferences")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task { await loadPlayersIfNeeded() }
        }
    }

    // MARK: - Add a reporter

    @ViewBuilder
    private func addReporterSection(prefs: FeedPreferencesStore) -> some View {
        Section {
            HStack {
                Image(systemName: "at")
                    .dsFont(14)
                    .foregroundStyle(Color.dsBluesky)
                TextField("Bluesky handle", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { Task { await validate() } }
                    .onChange(of: searchText) { _, _ in searchState = .idle }
                if case .loading = searchState { ProgressView() }
            }
            searchResultRow(prefs: prefs)
            ForEach(prefs.addedReporters) { r in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.displayName).dsFont(15, weight: .semibold)
                        Text("@\(r.handle)").dsFont(12).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Remove") { prefs.removeReporter(handle: r.handle) }
                        .dsFont(13, weight: .semibold)
                        .foregroundStyle(Color.dsError)
                        .buttonStyle(.plain)
                }
            }
        } header: { Text("Add a reporter") } footer: {
            Text("Follow any Bluesky reporter or outlet. We check they cover NWSL before adding.")
        }
    }

    @ViewBuilder
    private func searchResultRow(prefs: FeedPreferencesStore) -> some View {
        switch searchState {
        case .idle, .loading:
            EmptyView()
        case .notFound:
            Label("No NWSL posts found for this handle", systemImage: "xmark.circle")
                .dsFont(13).foregroundStyle(.secondary)
        case .failed:
            Label("Couldn't check that handle — try again", systemImage: "exclamationmark.triangle")
                .dsFont(13).foregroundStyle(.secondary)
        case let .found(handle, displayName):
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName).dsFont(15, weight: .semibold)
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill").dsFont(12).foregroundStyle(Color.dsSuccess)
                        Text("Active · @\(handle)").dsFont(12).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if prefs.isReporterAdded(handle: handle) {
                    Text("Added").dsFont(13, weight: .semibold).foregroundStyle(.secondary)
                } else {
                    Button("Add") {
                        prefs.addReporter(.init(handle: handle, displayName: displayName))
                    }
                    .dsFont(14, weight: .bold)
                    .foregroundStyle(Color.dsBluesky)
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func validate() async {
        let raw = searchText.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "@", with: "")
        guard !raw.isEmpty else { return }
        searchState = .loading
        do {
            let result = try await content.validateReporter(handle: raw)
            if result.found, result.hasNWSLPosts == true {
                searchState = .found(handle: raw, displayName: result.displayName ?? raw)
            } else {
                searchState = .notFound
            }
        } catch {
            searchState = .failed
        }
    }

    // MARK: - Follow players (inline "your teams")

    @ViewBuilder
    private func followPlayersSection(prefs: FeedPreferencesStore) -> some View {
        let followed = Set(followedTeamAbbrs)
        let byTeam = Dictionary(grouping: players.filter { followed.contains($0.team) }, by: \.team)
        Section {
            ForEach(followedTeamAbbrs.filter { byTeam[$0]?.isEmpty == false }, id: \.self) { abbr in
                teamHeaderRow(abbr: abbr, following: true)
                ForEach(byTeam[abbr] ?? []) { player in
                    playerToggleRow(player, isOwnTeam: true, prefs: prefs)
                }
            }
            NavigationLink {
                PlayerBrowseView(players: players, followedTeamAbbrs: followedTeamAbbrs, teamNames: teamNames)
                    .environment(preferences)
            } label: {
                HStack {
                    Text("Browse all players").dsFont(15, weight: .semibold).foregroundStyle(Color.dsAccent)
                    Spacer()
                }
            }
        } header: { Text("Follow players") } footer: {
            Text("Featuring \(players.isEmpty ? "national-team" : "\(players.count)") players — more coming. Follow stars beyond your teams in Browse all.")
        }
    }

    private func teamHeaderRow(abbr: String, following: Bool) -> some View {
        HStack(spacing: 8) {
            TeamLogo(urlString: nil, teamAbbreviation: abbr, size: 22)
            Text((teamNames[abbr] ?? abbr).uppercased())
                .dsFont(12, weight: .bold)
                .foregroundStyle(.secondary)
            if following {
                Text("FOLLOWING").dsFont(12, weight: .bold)
                    .foregroundStyle(Color.dsSuccess)
            }
            Spacer()
        }
        .listRowSeparator(.hidden)
    }

    private func playerToggleRow(_ player: FeedPlayer, isOwnTeam: Bool, prefs: FeedPreferencesStore) -> some View {
        let binding = Binding(
            get: { prefs.isPlayerFollowed(player.id, isOwnTeam: isOwnTeam) },
            set: { prefs.setPlayerFollowed(player.id, $0, isOwnTeam: isOwnTeam) }
        )
        return Toggle(isOn: binding) { Text(player.name).dsFont(15) }
    }

    // MARK: - Sources row (existing + ADDED badge)

    private func sourceRow(_ source: FeedViewModel.Source, prefs: FeedPreferencesStore) -> some View {
        let shown = Binding(
            get: { !prefs.isMuted(source.name) },
            set: { prefs.setMuted(source.name, !$0) }
        )
        return Toggle(isOn: shown) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.name).dsFont(15, weight: .semibold)
                    Text(source.detail).dsFont(12).foregroundStyle(.secondary)
                }
                if source.isAdded {
                    Text("ADDED").dsFont(12, weight: .bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().fill(Color.dsBluesky))
                }
            }
        }
    }

    private func loadPlayersIfNeeded() async {
        guard !didLoadPlayers else { return }
        didLoadPlayers = true
        players = (try? await content.playerDirectory()) ?? []
    }
}
