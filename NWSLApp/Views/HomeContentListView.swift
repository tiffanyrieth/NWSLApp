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
    /// AND its `selectedFilter` (the link "respects the active filter").
    let viewModel: HomeViewModel
    @Environment(FollowingStore.self) private var following

    var body: some View {
        let cards = viewModel.allFollowedTeamContent(following: following)
        ScrollView {
            LazyVStack(spacing: 14) {
                HomeContentChips(viewModel: viewModel)
                if cards.isEmpty {
                    Text("Nothing here right now — try a different filter.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.dsFgSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                } else {
                    ForEach(cards) { card in
                        ContentCardView(
                            card: card,
                            club: viewModel.club(forAbbreviation: card.teamAbbreviation ?? "")
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
}

/// The Home content-type chip bar ([All][Videos][News][Social]) — the same pill
/// component + pattern as the Feed tab, so users learn it once. Shared by Home
/// Module 1 and the See-more list; both drive the one `selectedFilter` on the
/// HomeViewModel they share.
struct HomeContentChips: View {
    let viewModel: HomeViewModel

    var body: some View {
        // A plain HStack, NOT a horizontal ScrollView. The four short fixed chips fit
        // any iPhone width, and the nested horizontal ScrollView (inside the vertical
        // hub ScrollView) leaked chip taps straight through to the first content
        // card's button — tapping a chip opened that card's URL in the browser instead
        // of filtering (bug #3). Without the nested scroll, the chips are ordinary
        // sibling buttons and capture their own taps.
        HStack(spacing: 8) {
            ForEach(HomeContentFilter.allCases, id: \.self) { filter in
                Chip(label: filter.label, isActive: viewModel.selectedFilter == filter) {
                    viewModel.selectedFilter = filter
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}
