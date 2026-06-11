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
//   3. Play                     — games (Trivia, Bracket Battle, Predict the XI).
//   4. Coming up                — a compact next-match strip per followed club.
//  ("Around the league" was removed — it duplicated the Schedule tab.)
//
//  Home owns no season or directory data: it reads the shared MatchStore,
//  ClubStore, and FollowingStore from the environment and derives everything
//  through HomeViewModel. The only thing it loads of its own are two TEMP content
//  seeds (Modules 1 & 2), via HomeViewModel.loadContent().
//

import SwiftUI

struct HomeView: View {
    @State private var viewModel = HomeViewModel()
    // Lets Home's empty state re-present the picker after onboarding is done.
    @State private var showTeamPicker = false
    // Drives the one-time post-onboarding "save your picks" sign-in prompt.
    @State private var showSignInPrompt = false
    // The profile avatar button's destination (a placeholder until the Profile
    // screen ships in its own phase).
    @State private var showProfile = false
    // Tracks the Module-2 spotlight carousel's current card, for the scroll dots.
    @State private var activeSpotlightID: String?
    @Environment(FollowingStore.self) private var following
    @Environment(MatchStore.self) private var matchStore
    @Environment(ClubStore.self) private var clubStore
    @Environment(TriviaStore.self) private var trivia
    @Environment(BracketStore.self) private var bracket
    @Environment(PredictionStore.self) private var predict
    @Environment(AuthStore.self) private var auth
    // Cross-tab navigation (Module 4's "Full schedule →" jumps to Schedule).
    @Environment(AppRouter.self) private var router

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
            // Hand the view model the shared stores, load the (TEMP) content
            // seeds, then load the shared stores once (guarding on .idle so
            // re-selecting the tab — or another screen having loaded them first —
            // doesn't refetch). Seeds load first so they're ready by the time the
            // stores report .loaded and the hub renders.
            viewModel.store = matchStore
            viewModel.clubStore = clubStore
            await viewModel.loadContent()
            if case .idle = matchStore.state { await matchStore.load() }
            if case .idle = clubStore.state { await clubStore.load() }
        }
        .sheet(isPresented: $showTeamPicker) {
            NavigationStack { OnboardingView() }
        }
        // Present the one-time sign-in prompt the first time the hub shows after
        // onboarding. `initial: true` also catches users who onboarded before this
        // feature existed. Marking it seen at present-time guarantees once-ever.
        .onChange(of: following.hasOnboarded, initial: true) { _, _ in
            presentSignInPromptIfNeeded()
        }
        .sheet(isPresented: $showSignInPrompt) {
            SignInPromptView()
        }
    }

    /// Show the post-onboarding sign-in prompt once, ever: only when the user has
    /// onboarded, hasn't already seen it, and isn't already signed in. Skipping is
    /// fine — the app works identically without an account.
    private func presentSignInPromptIfNeeded() {
        guard following.hasOnboarded,
              !following.hasSeenSignInPrompt,
              !auth.isSignedIn else { return }
        following.markSignInPromptSeen()
        showSignInPrompt = true
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { profileAvatarButton }
        }
        .sheet(isPresented: $showProfile) { ProfileView() }
        .refreshable { await reload() }
    }

    // Top-right avatar button → the Profile screen (account, notifications, follows).
    private var profileAvatarButton: some View {
        Button { showProfile = true } label: {
            ZStack {
                Circle().fill(Color.dsBgCard)
                Image(systemName: "person.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.dsFgSecondary)
            }
            .frame(width: 32, height: 32)
            .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
        }
        .accessibilityLabel("Profile")
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
        .background(Color.dsBgGrouped)
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
                    ForEach(items) { card in
                        ContentCardView(
                            card: card,
                            club: viewModel.club(forAbbreviation: card.teamAbbreviation ?? "")
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
                .foregroundStyle(Color.dsFgSecondary)
            Text("Follow your teams to fill your home feed with their latest content.")
                .font(.subheadline)
                .foregroundStyle(Color.dsFgSecondary)
                .multilineTextAlignment(.center)
            Button("Choose your teams") { showTeamPicker = true }
                .buttonStyle(.borderedProminent)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(Color.dsBgCard)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous))
    }

    // MARK: - Module 2: Get to know your players (spotlight)

    @ViewBuilder
    private var getToKnowYourPlayers: some View {
        let spotlights = viewModel.spotlights(following: following)
        if !spotlights.isEmpty {
            section(
                "Get to know your players",
                subtitle: "A new spotlight every week for each team you follow"
            ) {
                VStack(spacing: 10) {
                    // Equal-weight cards in a snapping horizontal carousel (one per
                    // followed team) — same visual weight, no full-size-vs-tap split.
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
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
                                // 85% of the carousel width so the next card peeks.
                                .containerRelativeFrame(.horizontal, count: 100, span: 85, spacing: 0)
                                .id(spotlight.id)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.viewAligned)
                    .scrollPosition(id: $activeSpotlightID)
                    .onAppear { if activeSpotlightID == nil { activeSpotlightID = spotlights.first?.id } }

                    if spotlights.count > 1 {
                        let active = spotlights.firstIndex { $0.id == activeSpotlightID } ?? 0
                        scrollDots(count: spotlights.count, activeIndex: active)
                    }
                }
            }
        }
    }

    // MARK: - Module 3: Fan Zone (the games)

    private var playSection: some View {
        section(
            "Fan Zone",
            subtitle: "Test your NWSL knowledge and compete with other fans",
            accessory: { activeGamesIndicator }
        ) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // Ordered most time-sensitive first. Predict the XI is
                    // matchday-driven AND inherently personal (you predict YOUR
                    // team's lineup), so it only appears once the user follows a
                    // club; Bracket Battle and Daily Trivia show for everyone.
                    if !following.followedIDs.isEmpty {
                        NavigationLink { PredictXIView() } label: { predictGameCard }
                            .buttonStyle(.plain)
                    }
                    NavigationLink { BracketBattleView() } label: { bracketGameCard }
                        .buttonStyle(.plain)
                    NavigationLink { DailyTriviaView() } label: { triviaGameCard }
                        .buttonStyle(.plain)
                }
                .padding(.horizontal, 2)
            }
        }
    }

    // "● 2 active" — a teal dot + count of games with something to do right now.
    @ViewBuilder
    private var activeGamesIndicator: some View {
        let n = activeGameCount
        if n > 0 {
            HStack(spacing: 5) {
                Circle().fill(Color.dsGameBracket).frame(width: 6, height: 6)
                Text("\(n) active")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.dsFgSecondary)
            }
        }
    }

    private var activeGameCount: Int {
        var n = 0
        if !following.followedIDs.isEmpty { n += 1 }   // Predict is shown + playable
        if !bracket.isComplete { n += 1 }
        if !trivia.hasPlayedToday { n += 1 }
        return n
    }

    private var triviaGameCard: some View {
        GameCard(
            emoji: "🧠", title: "Daily Trivia",
            statusLine: trivia.hasPlayedToday ? "Done today ✓" : "Play now",
            accent: .dsGameTrivia, completed: trivia.hasPlayedToday,
            badge: trivia.streak > 0 ? "\(trivia.streak)" : nil, badgeIcon: "🔥"
        )
    }

    private var bracketGameCard: some View {
        GameCard(
            emoji: "🏆", title: "Bracket Battle",
            statusLine: bracketStateLine,
            accent: .dsGameBracket, completed: bracket.isComplete,
            badge: bracket.points > 0 ? "\(bracket.points)" : nil, badgeIcon: "🏆"
        )
    }

    private var predictGameCard: some View {
        GameCard(
            emoji: "⚽", title: "Predict the XI",
            statusLine: predict.hasPredicted ? "\(predict.seasonPoints) pts" : "Predict now",
            accent: .dsGamePredict,
            badge: predict.seasonPoints > 0 ? "\(predict.seasonPoints)" : nil, badgeIcon: "⚽"
        )
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

    // MARK: - Module 4: Coming up (compact schedule strip)

    @ViewBuilder
    private var comingUp: some View {
        let fixtures = viewModel.nextMatches(following: following)
        if !fixtures.isEmpty {
            section("Coming up", accessory: { fullScheduleLink }) {
                VStack(spacing: 8) {
                    ForEach(fixtures) { ComingUpRow(fixture: $0) }
                }
            }
        }
    }

    // Jumps to the Schedule tab (via the shared AppRouter).
    private var fullScheduleLink: some View {
        Button { router.selectedTab = .schedule } label: {
            Text("Full schedule →")
                .font(.system(size: 12))
                .foregroundStyle(Color.dsAccent)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Shared building blocks

    @ViewBuilder
    private func section<Content: View, Accessory: View>(
        _ title: String,
        subtitle: String? = nil,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.dsFgPrimary)
                    Spacer(minLength: 8)
                    accessory()
                }
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.dsFgSecondary)
                }
            }
            content()
        }
    }

    /// Module-2 carousel scroll-position dots: one per spotlight, current filled.
    private func scrollDots(count: Int, activeIndex: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(i == activeIndex ? Color.dsFgSecondary : Color.dsFgQuaternary)
                    .frame(width: 6, height: 6)
            }
        }
        .frame(maxWidth: .infinity)
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
        await clubStore.load()
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
        .environment(AppRouter())
        .environment(FollowingStore())
        .environment(MatchStore())
        .environment(ClubStore())
        .environment(TriviaStore())
        .environment(BracketStore())
        .environment(PredictionStore())
        .environment(AuthStore())
        .environment(NotificationPreferencesStore())
}
