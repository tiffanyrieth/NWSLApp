//
//  BrowseAllTeamsView.swift
//  NWSLApp
//
//  "Browse all national teams" — pushed from the Competitions view. A searchable 2-column
//  grid over a DATA-DRIVEN set: the proxy `/national-teams` union of ESPN's women's coverage
//  (via `NationalTeamDirectoryStore`), so it reflects real coverage and picks up future ESPN
//  additions with no app release — no hand-maintained list here. The curated FEATURED teams are
//  always the head of it (their bundled vector flags); everyone else uses ESPN's flag
//  (download+cache). Uses the SAME `NationalTeamCard` as the Competitions hub — one visual
//  language. Honest states throughout: loading spinner, error+retry, and a real empty result —
//  never a blank screen or an endless spinner.
//

import SwiftUI

struct BrowseAllTeamsView: View {
    @State private var store = NationalTeamDirectoryStore()
    @State private var query = ""

    private let columns = [GridItem(.flexible(), spacing: 12),
                           GridItem(.flexible(), spacing: 12)]

    private func results(_ teams: [NationalTeam]) -> [NationalTeam] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return teams }
        return teams.filter {
            $0.name.localizedCaseInsensitiveContains(q)
                || $0.code.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        Group {
            switch store.state {
            case .idle, .loading:
                ProgressView("Loading teams…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed:
                errorState
            case .loaded(let teams):
                grid(results(teams))
            }
        }
        .background(Color.dsBgGrouped)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search by name or code")
        .navigationContextLabel("National Teams")
        .task { await store.load() }
    }

    @ViewBuilder
    private func grid(_ teams: [NationalTeam]) -> some View {
        ScrollView {
            if teams.isEmpty {
                // Distinguish "no search match" from "no coverage" — both honest, neither blank.
                Text(query.isEmpty ? "No national teams available right now."
                                   : "No teams match “\(query)”.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.dsFgSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.top, 40)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(teams) { NationalTeamCard($0) }
                }
                .padding(16)
            }
        }
    }

    private var errorState: some View {
        VStack(spacing: 12) {
            Text("Couldn't load teams — tap to retry")
                .font(.system(size: 14))
                .foregroundStyle(Color.dsFgSecondary)
                .multilineTextAlignment(.center)
            Button("Try again") { Task { await store.load() } }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

#Preview {
    NavigationStack {
        BrowseAllTeamsView()
            .environment(FollowingStore())
            .environment(TeamAlertStore())
    }
}
