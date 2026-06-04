//
//  TeamDetailView.swift
//  NWSLApp
//
//  A club's page, pushed from the Teams directory. Three stacked sections:
//   • Header — crest + name + the same Follow star used in the Teams list, so
//     toggling here reflects everywhere (shared FollowingStore).
//   • Schedule — that club's matches, sliced from the shared MatchStore (no
//     extra fetch) and rendered with the existing MatchCard.
//   • Roster — the squad from ESPN's roster endpoint, grouped by position.
//
//  No NavigationStack of its own: it's pushed onto the Teams tab's stack, so the
//  back affordance comes for free (UI rule: every drilled-in view is reversible).
//  The roster loads independently of the schedule, so a roster failure never
//  blanks the header + matches that already rendered.
//

import SwiftUI

struct TeamDetailView: View {
    let club: Club

    @State private var viewModel = TeamDetailViewModel()
    @Environment(FollowingStore.self) private var following
    @Environment(MatchStore.self) private var matchStore

    var body: some View {
        List {
            headerSection
            scheduleSection
            rosterContent
        }
        .listStyle(.insetGrouped)
        .navigationTitle(club.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // The schedule slice reuses the shared season store. If a user lands
            // here before Schedule has loaded it, kick the load; otherwise reuse
            // what's already there. Then load this club's roster.
            if case .idle = matchStore.state { await matchStore.load() }
            await viewModel.load(clubID: club.id)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        Section {
            HStack(spacing: 16) {
                TeamLogo(urlString: club.logoURL, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(club.displayName)
                        .font(.title2.weight(.bold))
                    if !club.abbreviation.isEmpty {
                        Text(club.abbreviation)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                followButton
            }
            .padding(.vertical, 8)
        }
    }

    private var followButton: some View {
        let isFollowing = following.isFollowing(club)
        return Button {
            following.toggle(club)
        } label: {
            Image(systemName: isFollowing ? "star.fill" : "star")
                .foregroundStyle(isFollowing ? .yellow : .secondary)
                .imageScale(.large)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(isFollowing ? "Unfollow \(club.displayName)" : "Follow \(club.displayName)")
    }

    // MARK: - Schedule slice

    @ViewBuilder
    private var scheduleSection: some View {
        Section("Schedule") {
            let matches = matchStore.matches(for: club)
            if !matches.isEmpty {
                ForEach(matches) { event in
                    MatchCard(event: event)
                        // Let the card's own surface sit on the grouped
                        // background instead of an inset List row.
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowBackground(Color.clear)
                }
            } else {
                scheduleEmptyState
            }
        }
    }

    @ViewBuilder
    private var scheduleEmptyState: some View {
        switch matchStore.state {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
        case .error(let message):
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
        case .loaded:
            // Loaded, but nothing matched this club — surfaces the abbreviation
            // join breaking rather than hiding it (see MatchStore.matches).
            Text("No matches found for this club.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Roster

    @ViewBuilder
    private var rosterContent: some View {
        switch viewModel.state {
        case .idle, .loading:
            Section("Roster") {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        case .error(let message):
            Section("Roster") {
                VStack(spacing: 8) {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Try again") {
                        Task { await viewModel.load(clubID: club.id) }
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
        case .loaded:
            ForEach(viewModel.positionGroups) { group in
                Section(group.label) {
                    ForEach(group.athletes) { athlete in
                        PlayerRow(athlete: athlete)
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        TeamDetailView(club: Club(
            id: "21422",
            displayName: "Angel City FC",
            abbreviation: "LA",
            logoURL: nil
        ))
    }
    .environment(FollowingStore())
    .environment(MatchStore())
}
