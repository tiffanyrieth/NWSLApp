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
//  Note: rows aren't tappable yet. A club → detail page (roster, schedule) is
//  the next milestone; we don't ship navigation that goes nowhere.
//

import SwiftUI

struct TeamsView: View {
    @State private var viewModel = TeamsViewModel()
    @Environment(FollowingStore.self) private var following

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Teams")
                .refreshable { await viewModel.load() }
        }
        // Load once on first appearance; don't refetch every time the tab is
        // re-selected (pull-to-refresh covers manual reloads).
        .task {
            if case .idle = viewModel.state { await viewModel.load() }
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
        }
        .listStyle(.insetGrouped)
    }

    private func row(for club: Club) -> some View {
        HStack(spacing: 12) {
            TeamLogo(urlString: club.logoURL, size: 32)
            Text(club.displayName)
            Spacer()
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
}
