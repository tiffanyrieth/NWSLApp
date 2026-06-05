//
//  HomeView.swift
//  NWSLApp
//
//  The Home tab — the app's your-teams-first hub, "alive between matchdays."
//  Until the user has been through onboarding it renders the "Make it yours"
//  team picker in place (tab bar stays visible); afterwards it shows the hub.
//
//  Modules, top to bottom (per Reference/Design/home-tab-design-spec.md):
//   1. Your next matches — one card per followed club's next fixture (real).
//   2. From your teams   — team social/video content (intentional placeholder:
//                          no content endpoint exists yet).
//   3. Play              — games/challenges (intentional placeholder: spec's
//                          reserved structural slot; no games engine yet).
//   4. Spotlight         — opt-in only, NOT shown by default (omitted here).
//   5. Around the league — the next matchday's games league-wide (real).
//
//  Home owns no season data: it reads the shared MatchStore + FollowingStore
//  from the environment and derives everything through HomeViewModel. The only
//  fetch it triggers is the club directory (to resolve followed IDs → Clubs).
//

import SwiftUI

struct HomeView: View {
    @State private var viewModel = HomeViewModel()
    // Lets Home's empty state re-present the picker after onboarding is done.
    @State private var showTeamPicker = false
    @Environment(FollowingStore.self) private var following
    @Environment(MatchStore.self) private var matchStore

    var body: some View {
        NavigationStack {
            Group {
                if following.hasOnboarded {
                    hubContent
                } else {
                    // First open: pick your teams (rides this NavigationStack so
                    // the tab bar stays visible, per the spec).
                    OnboardingView()
                }
            }
        }
        .task {
            // Hand the view model the shared store, then load both sources once
            // (guarding on .idle so re-selecting the tab doesn't refetch).
            viewModel.store = matchStore
            if case .idle = matchStore.state { await matchStore.load() }
            if case .idle = viewModel.clubsState { await viewModel.loadClubs() }
        }
        .sheet(isPresented: $showTeamPicker) {
            NavigationStack { OnboardingView() }
        }
    }

    // MARK: - Hub

    @ViewBuilder
    private var hubContent: some View {
        Group {
            if let message = errorMessage {
                errorView(message)
            } else if !isReady {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                hub
            }
        }
        .navigationTitle("Home")
        .refreshable { await reload() }
    }

    private var hub: some View {
        ScrollView {
            VStack(spacing: 28) {
                yourNextMatches
                fromYourTeams
                playSection
                aroundTheLeague
            }
            .padding(.vertical, 8)
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Module 1: Your next matches

    @ViewBuilder
    private var yourNextMatches: some View {
        let fixtures = viewModel.nextMatches(following: following)
        section("Your next matches") {
            if fixtures.isEmpty {
                followPrompt
            } else {
                VStack(spacing: 12) {
                    ForEach(fixtures) { NextMatchCard(fixture: $0) }
                }
            }
        }
    }

    // Shown when no followed club has a fixture to surface — usually because the
    // user follows nobody (e.g. unfollowed everyone after onboarding).
    private var followPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "star")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Follow your teams to see their next matches here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Choose your teams") { showTeamPicker = true }
                .buttonStyle(.borderedProminent)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Module 2: From your teams (placeholder)

    private var fromYourTeams: some View {
        section("From your teams") {
            comingSoonCard(
                icon: "play.rectangle.on.rectangle",
                title: "Team content, coming soon",
                message: "Posts and videos from your teams' own channels will land here."
            )
        }
    }

    // MARK: - Module 3: Play (placeholder, horizontal slot reserved)

    private var playSection: some View {
        section("Play") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    playCard(icon: "brain.head.profile", title: "Daily Trivia")
                    playCard(icon: "list.number", title: "Predict the XI")
                    playCard(icon: "trophy", title: "Bracket Battle")
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private func playCard(icon: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text("Coming soon")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(width: 150, height: 120, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Module 5: Around the league

    @ViewBuilder
    private var aroundTheLeague: some View {
        let games = viewModel.aroundTheLeague
        if !games.isEmpty {
            section("Around the league", subtitle: viewModel.aroundTheLeagueLabel) {
                VStack(spacing: 12) {
                    ForEach(games) { MatchCard(event: $0) }
                }
            }
        }
    }

    // MARK: - Shared building blocks

    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.title3.weight(.bold))
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            content()
        }
    }

    private func comingSoonCard(icon: String, title: String, message: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - State plumbing

    private var errorMessage: String? {
        if case .error(let m) = viewModel.clubsState { return m }
        if case .error(let m) = matchStore.state { return m }
        return nil
    }

    private var isReady: Bool {
        if case .loaded = viewModel.clubsState, case .loaded = matchStore.state { return true }
        return false
    }

    private func reload() async {
        await matchStore.load()
        await viewModel.loadClubs()
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Button("Try again") { Task { await reload() } }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    HomeView()
        .environment(FollowingStore())
        .environment(MatchStore())
}
