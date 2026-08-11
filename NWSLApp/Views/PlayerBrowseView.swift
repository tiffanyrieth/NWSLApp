//
//  PlayerBrowseView.swift
//  NWSLApp
//
//  Phase 3 "Follow players" — pushed from Content Preferences. Browse the featured
//  national-team players and follow ones beyond your teams (an SD fan can follow a
//  Washington star). A team-filter chip bar (followed teams first) narrows the grouped
//  list. Own-team players are pre-followed; toggling them here writes the same
//  FeedPreferencesStore the Feed reads. The 34-player pool is the proxy directory; the
//  chip filter + grouped list scale unchanged when it grows.
//

import SwiftUI

struct PlayerBrowseView: View {
    let players: [FeedPlayer]
    let followedTeamAbbrs: [String]
    let teamNames: [String: String]

    @Environment(FeedPreferencesStore.self) private var preferences
    @State private var teamFilter: String? = nil   // nil = All

    private var followedSet: Set<String> { Set(followedTeamAbbrs) }

    /// Teams that have featured players — followed teams first, then alphabetical by name.
    private var teamsWithPlayers: [String] {
        Array(Set(players.map(\.team))).sorted { a, b in
            let fa = followedSet.contains(a), fb = followedSet.contains(b)
            if fa != fb { return fa }
            return (teamNames[a] ?? a) < (teamNames[b] ?? b)
        }
    }

    private var visibleTeams: [String] {
        if let teamFilter { return teamsWithPlayers.filter { $0 == teamFilter } }
        return teamsWithPlayers
    }

    var body: some View {
        @Bindable var prefs = preferences
        List {
            Section {
                Text("Follow players beyond your teams. Their posts appear in your Feed.")
                    .dsFont(13).foregroundStyle(Color.dsFgSecondary)
                    .listRowSeparator(.hidden)
                chipBar
                    .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 4, trailing: 0))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            ForEach(visibleTeams, id: \.self) { abbr in
                let isOwn = followedSet.contains(abbr)
                Section {
                    ForEach(players.filter { $0.team == abbr }) { player in
                        let binding = Binding(
                            get: { prefs.isPlayerFollowed(player.id, isOwnTeam: isOwn) },
                            set: { prefs.setPlayerFollowed(player.id, $0, isOwnTeam: isOwn) }
                        )
                        Toggle(isOn: binding) { Text(player.name).dsFont(15) }
                    }
                } header: { teamHeader(abbr, following: isOwn) }
            }
            Section {
                Text("Currently featuring \(players.count) players — more coming.")
                    .dsFont(12).foregroundStyle(Color.dsFgSecondary)
            }
        }
        .navigationTitle("Follow players")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var chipBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(label: "All", abbr: nil, crest: false)
                ForEach(teamsWithPlayers, id: \.self) { abbr in
                    chip(label: abbr, abbr: abbr, crest: true)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func chip(label: String, abbr: String?, crest: Bool) -> some View {
        let selected = teamFilter == abbr
        return Button {
            teamFilter = selected ? nil : abbr
        } label: {
            HStack(spacing: 5) {
                if crest, let abbr { TeamLogo(urlString: nil, teamAbbreviation: abbr, size: 18) }
                Text(label).dsFont(13, weight: .semibold)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Capsule().fill(selected ? Color.dsAccent : Color.dsBgCard))
            .foregroundStyle(selected ? Color.white : Color.dsFgPrimary)
        }
        .buttonStyle(.plain)
    }

    private func teamHeader(_ abbr: String, following: Bool) -> some View {
        HStack(spacing: 8) {
            TeamLogo(urlString: nil, teamAbbreviation: abbr, size: 22)
            Text((teamNames[abbr] ?? abbr).uppercased()).dsFont(12, weight: .bold).foregroundStyle(Color.dsFgSecondary)
            if following {
                Text("FOLLOWING").dsFont(12, weight: .bold).foregroundStyle(Color.dsSuccess)
            }
            Spacer()
        }
    }
}
