//
//  HomeContentListView.swift
//  NWSLApp
//
//  The "See more from your teams →" destination (QOL Change 1). Home Module 1 shows a
//  round-robin-balanced, capped slice; this is the full firehose behind it — ALL
//  followed-team content, no cap, reverse-chronological, honoring the active content
//  chip. It reads the already-fetched cards off the shared HomeViewModel (no new
//  fetch) and rides Home's NavigationStack, so the back affordance is free.
//

import SwiftUI

struct HomeContentListView: View {
    /// The same HomeViewModel instance as Home, so the list shares its fetched cards
    /// AND its `selectedTeam` (the link respects the active per-team chip).
    let viewModel: HomeViewModel
    @Environment(FollowingStore.self) private var following

    var body: some View {
        let teams = viewModel.followedTeamAbbreviations(following: following)
        let cards = viewModel.allFollowedTeamContent(following: following)
        ScrollView {
            LazyVStack(spacing: 14) {
                if teams.count >= 2 {
                    HomeTeamChips(viewModel: viewModel, teams: teams)
                }
                if cards.isEmpty {
                    Text(emptyText)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.dsFgSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                } else {
                    ForEach(cards) { card in
                        ContentCardView(
                            card: card,
                            club: viewModel.club(forAbbreviation: card.teamAbbreviation ?? ""),
                            hideTeamIdentity: teams.count <= 1
                        )
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .background(Color.dsBgGrouped)
        .navigationTitle("From your teams")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var emptyText: String {
        if let team = viewModel.selectedTeam { return "No content from \(team) right now." }
        return "Nothing here right now."
    }
}

/// The Home per-team chip bar: [All] + one chip per followed team (abbreviations).
/// Drives the shared HomeViewModel's `selectedTeam` (nil = All). A plain HStack, NOT
/// a horizontal ScrollView — a nested scroll inside the hub scroll is the thing that
/// caused the chip tap-leak, and the few short chips fit any iPhone width.
struct HomeTeamChips: View {
    let viewModel: HomeViewModel
    let teams: [String]

    var body: some View {
        HStack(spacing: 8) {
            Chip(label: "All", isActive: viewModel.selectedTeam == nil) {
                viewModel.selectedTeam = nil
            }
            ForEach(teams, id: \.self) { abbr in
                Chip(label: abbr, isActive: viewModel.selectedTeam == abbr) {
                    viewModel.selectedTeam = abbr
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}
