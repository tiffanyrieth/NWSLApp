//
//  TeamsView.swift
//  NWSLApp
//
//  The Teams tab: a directory of all NWSL clubs, each with a Follow toggle.
//  Following is the app's personalization lens (see FollowingStore) — so a
//  "Following" section floats followed clubs to the top, making the lens
//  visible the moment you tap a star. The full roster always shows below,
//  end-to-end (UI rule: no truncation).
//
//  The FollowingStore arrives via the SwiftUI environment (injected once in
//  RootTabView), not constructed here — so this screen and future ones share
//  the same single source of truth for who you follow.
//
//  Each row is a NavigationLink into TeamDetailView (crest, club schedule,
//  roster, Follow). The destination reads the shared MatchStore + FollowingStore
//  from the environment, both injected in RootTabView.
//

import SwiftUI

struct TeamsView: View {
    @State private var viewModel = TeamsViewModel()
    @State private var path = NavigationPath()
    @Environment(FollowingStore.self) private var following
    // The shared club directory (injected in RootTabView); the view model reads
    // its state/clubs through this.
    @Environment(ClubStore.self) private var clubStore

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("Teams")
                .navigationDestination(for: Club.self) { club in
                    TeamDetailView(club: club)
                }
                .refreshable { await viewModel.load() }
        }
        // Load once on first appearance; don't refetch every time the tab is
        // re-selected (pull-to-refresh covers manual reloads).
        .task {
            viewModel.clubStore = clubStore
            if case .idle = clubStore.state { await viewModel.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("Loading teams…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let message):
            errorView(message)
        case .loaded:
            directory
        }
    }

    private var directory: some View {
        let followed = viewModel.clubs.filter { following.isFollowing($0) }
        return List {
            if !followed.isEmpty {
                Section("Following") {
                    ForEach(followed) { row(for: $0) }
                }
            }
            Section("All Clubs") {
                ForEach(viewModel.clubs) { row(for: $0) }
            }

            // A way back into international competitions for anyone who skipped
            // them during onboarding (the only other place they're offered).
            Section {
                NavigationLink {
                    CompetitionsView()
                } label: {
                    Label("Follow competitions", systemImage: "globe")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func row(for club: Club) -> some View {
        // Navigation and the Follow star are SIBLING buttons, not nested: a
        // `Button` inside a `NavigationLink` swallows the row's navigation tap
        // (the star toggles, the rest of the row goes dead). So the row body is
        // its own button that pushes the club via the navigation path, and the
        // star is a separate button beside it — each owns its own taps.
        HStack(spacing: 12) {
            Button {
                path.append(club)
            } label: {
                HStack(spacing: 12) {
                    TeamLogo(urlString: club.logoURL, size: 32)
                    Text(club.displayName)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())   // whole left area is tappable
            }
            .buttonStyle(.plain)

            followButton(for: club)
        }
    }

    private func followButton(for club: Club) -> some View {
        let isFollowing = following.isFollowing(club)
        return Button {
            following.toggle(club)
        } label: {
            Image(systemName: isFollowing ? "star.fill" : "star")
                .foregroundStyle(isFollowing ? .yellow : .secondary)
                .imageScale(.large)
        }
        // .borderless so only the star toggles — not the whole row.
        .buttonStyle(.borderless)
        .accessibilityLabel(isFollowing ? "Unfollow \(club.displayName)" : "Follow \(club.displayName)")
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Button("Try again") {
                Task { await viewModel.load() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    TeamsView()
        .environment(FollowingStore())
        .environment(MatchStore())
        .environment(ClubStore())
}
