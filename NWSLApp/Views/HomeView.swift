//
//  HomeView.swift
//  NWSLApp
//
//  The Home tab — the app's your-teams-first hub, "alive between matchdays."
//  Until the user has been through onboarding it renders the "Make it yours"
//  team picker in place (tab bar stays visible); afterwards it shows the hub.
//
//  Modules, top to bottom (per Reference/Design/home-tab-design-spec.md —
//  content leads, schedule demoted):
//   1. From your teams          — team-channel content (the hook), real seeded.
//   2. Get to know your players — one weekly player spotlight (seeded).
//   3. Play                     — games/challenges (intentional placeholder).
//   4. Coming up                — a compact next-match strip per followed club.
//  ("Around the league" was removed — it duplicated the Schedule tab.)
//
//  Home owns no season data: it reads the shared MatchStore + FollowingStore from
//  the environment and derives everything through HomeViewModel. The fetches it
//  triggers are the club directory (followed IDs → Clubs) and two TEMP content
//  seeds (Modules 1 & 2), both via HomeViewModel.loadClubs().
//

import SwiftUI

struct HomeView: View {
    @State private var viewModel = HomeViewModel()
    // Lets Home's empty state re-present the picker after onboarding is done.
    @State private var showTeamPicker = false
    @Environment(FollowingStore.self) private var following
    @Environment(MatchStore.self) private var matchStore
    @Environment(TriviaStore.self) private var trivia
    @Environment(BracketStore.self) private var bracket

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
                fromYourTeams
                getToKnowYourPlayers
                playSection
                comingUp
            }
            .padding(.vertical, 8)
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Module 1: From your teams (the hook)

    @ViewBuilder
    private var fromYourTeams: some View {
        let items = viewModel.teamContent(following: following)
        section("From your teams") {
            if items.isEmpty {
                followPrompt
            } else {
                VStack(spacing: 14) {
                    ForEach(items) { item in
                        TeamContentCard(
                            item: item,
                            club: viewModel.club(forAbbreviation: item.teamAbbreviation)
                        )
                    }
                }
            }
        }
    }

    // Shown when the user follows nobody (so the lead module has nothing to show).
    private var followPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "star")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Follow your teams to fill your home feed with their latest content.")
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

    // MARK: - Module 2: Get to know your players (spotlight)

    @ViewBuilder
    private var getToKnowYourPlayers: some View {
        let spotlights = viewModel.spotlights(following: following)
        if !spotlights.isEmpty {
            section("Get to know your players") {
                VStack(spacing: 14) {
                    ForEach(spotlights) { spotlight in
                        NavigationLink {
                            PlayerSpotlightView(
                                spotlight: spotlight,
                                club: viewModel.club(forAbbreviation: spotlight.teamAbbreviation)
                            )
                        } label: {
                            PlayerSpotlightCard(
                                spotlight: spotlight,
                                club: viewModel.club(forAbbreviation: spotlight.teamAbbreviation)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Module 3: Play (placeholder, horizontal slot reserved)

    private var playSection: some View {
        section("Play", subtitle: "Test your NWSL knowledge and compete with other fans") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // Two built games — live entry points.
                    NavigationLink { DailyTriviaView() } label: { dailyTriviaCard }
                        .buttonStyle(.plain)
                    NavigationLink { BracketBattleView() } label: { bracketBattleCard }
                        .buttonStyle(.plain)
                    // Predict the XI remains an intentional "coming soon" placeholder.
                    playCard(icon: "list.number", title: "Predict the XI")
                }
                .padding(.horizontal, 2)
            }
        }
    }

    // The live Daily-Trivia card: indigo identity, with a state line that reads
    // "Done today" once played (and a streak flame when one's going).
    private var dailyTriviaCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.title2)
                    .foregroundStyle(.indigo)
                Spacer(minLength: 0)
                if trivia.streak > 0 {
                    Label("\(trivia.streak)", systemImage: "flame.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.orange)
                        .labelStyle(.titleAndIcon)
                }
            }
            Spacer(minLength: 0)
            Text("Daily Trivia")
                .font(.subheadline.weight(.semibold))
            Text(trivia.hasPlayedToday ? "Done today ✓" : "Play now")
                .font(.caption.weight(.semibold))
                .foregroundStyle(trivia.hasPlayedToday ? Color.secondary : .indigo)
        }
        .padding(16)
        .frame(width: 150, height: 120, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.indigo.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // The live Bracket-Battle card: teal identity, with a state line that reads
    // "Play now" → "Round n of N" → "Complete ✓" off the shared BracketStore, and
    // a points badge once the user has banked any.
    private var bracketBattleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "trophy.fill")
                    .font(.title2)
                    .foregroundStyle(.teal)
                Spacer(minLength: 0)
                if bracket.points > 0 {
                    Label("\(bracket.points)", systemImage: "trophy")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.teal)
                        .labelStyle(.titleAndIcon)
                }
            }
            Spacer(minLength: 0)
            Text("Bracket Battle")
                .font(.subheadline.weight(.semibold))
            Text(bracketStateLine)
                .font(.caption.weight(.semibold))
                .foregroundStyle(bracket.isComplete ? Color.secondary : .teal)
        }
        .padding(16)
        .frame(width: 150, height: 120, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.teal.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // "Play now" before any voting, "Complete ✓" once the final's closed, else the
    // current round ("Round 2 of 4"). roundCount falls back to 4 (the current
    // edition) until the game's been opened and stored it.
    private var bracketStateLine: String {
        if bracket.isComplete { return "Complete ✓" }
        if !bracket.hasStarted { return "Play now" }
        let total = bracket.roundCount > 0 ? bracket.roundCount : 4
        return "Round \(bracket.lockedRoundCount + 1) of \(total)"
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

    // MARK: - Module 4: Coming up (compact schedule strip)

    @ViewBuilder
    private var comingUp: some View {
        let fixtures = viewModel.nextMatches(following: following)
        if !fixtures.isEmpty {
            section("Coming up") {
                VStack(spacing: 8) {
                    ForEach(fixtures) { ComingUpRow(fixture: $0) }
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
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.bold))
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            content()
        }
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
        .environment(TriviaStore())
        .environment(BracketStore())
}
