//
//  BrowseAllTeamsView.swift
//  NWSLApp
//
//  "Browse all national teams" — pushed from the Competitions view. A searchable
//  2-column grid over the full `NationalTeam.all` set (the featured grid is just the
//  head of it), so a user can find a team that isn't one of the eight featured cards.
//  Uses the SAME `NationalTeamCard` as the Competitions hub — one visual language, no
//  grid-vs-list switch. The list is data-driven: adding a team is one more
//  `NationalTeam.all` entry, no code change here.
//

import SwiftUI

struct BrowseAllTeamsView: View {
    @State private var query = ""

    private let columns = [GridItem(.flexible(), spacing: 12),
                           GridItem(.flexible(), spacing: 12)]

    private var results: [NationalTeam] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return NationalTeam.all }
        return NationalTeam.all.filter {
            $0.name.localizedCaseInsensitiveContains(q)
                || $0.code.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        ScrollView {
            if results.isEmpty {
                Text("No teams match “\(query)”.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.dsFgSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(results) { NationalTeamCard($0) }
                }
                .padding(16)
            }
        }
        .background(Color.dsBgGrouped)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search by name or code")
        .navigationContextLabel("National Teams")
    }
}

#Preview {
    NavigationStack {
        BrowseAllTeamsView()
            .environment(FollowingStore())
            .environment(TeamAlertStore())
    }
}
