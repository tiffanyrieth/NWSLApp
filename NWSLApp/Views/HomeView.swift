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
    // Cross-tab navigation (Module 4's "Full schedule →" jumps to Schedule).
    @Environment(AppRouter.self) private var router

    var body: some View {
        NavigationStack {
            // Onboarding is gated above this view now (RootTabView shows OnboardingView
            // full-screen until `hasOnboarded`), so Home only ever renders the hub.
            hubContent
        }
        .task {
            // Hand the view model the shared stores, load the shared stores once
            // (guarding on .idle so re-selecting the tab — or another screen having
            // loaded them first — doesn't refetch), THEN load Module-1 content.
            // Content runs last because the live `/team-videos` route is scoped to
            // the followed clubs, which `loadContent` resolves from the now-loaded
            // ClubStore. The hub gates on clubs+matches being `.loaded` anyway, so
            // content loading after them costs nothing visible.
            viewModel.store = matchStore
            viewModel.clubStore = clubStore
            if case .idle = matchStore.state { await matchStore.load() }
            if case .idle = clubStore.state { await clubStore.load() }
            await viewModel.loadContent(following: following)
            await loadBracketSummary()
        }
        // A newly-followed (or unfollowed) team should change Module 1 without a
        // manual refresh — refetch the live content scoped to the new followed set
        // (the deferred "refetch-on-follows-change" item). Also reset the per-team
        // chip if the team it pointed at was just unfollowed.
        .onChange(of: following.followedIDs) {
            viewModel.reconcileSelectedTeam(following: following)
            Task { await viewModel.loadContent(following: following, force: true) }
        }
        .sheet(isPresented: $showTeamPicker) {
            NavigationStack { OnboardingView() }
        }
    }

    /// Cache the active Bracket edition summary so the Fan Zone card can show/hide
    /// (the visibility gate) and render its status without opening the game. The
    /// full edition + real votes load when the game is opened (BracketService).
    private func loadBracketSummary() async {
        let service = BracketService()
        do {
            if let edition = try await service.currentEdition() {
                bracket.adopt(summary: .init(
                    id: edition.id, title: edition.title,
                    currentRoundRaw: edition.currentRound.rawValue,
                    roundClosesAt: edition.roundClosesAt, isActive: true
                ))
            } else {
                // Genuinely no active edition → hide the Fan Zone card.
                bracket.clearActiveEdition()
            }
        } catch {
            // Online-only: a failed gate preload leaves the existing gate as-is —
            // opening the game surfaces the honest error. Don't fabricate or clear.
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
        // Custom large-title header (title + profile avatar) like the Schedule /
        // Standings facelift headers; the system nav bar is hidden so the header
        // owns the top edge.
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) { homeHeader }
        .sheet(isPresented: $showProfile) { ProfileView() }
        .refreshable { await reload() }
    }

    // Large "Home" title + the profile avatar button, drawn as one pinned header.
    private var homeHeader: some View {
        HStack(alignment: .center) {
            Text("Home")
                .dsFont(32, weight: .bold)
                .foregroundStyle(Color.dsFgPrimary)
            Spacer(minLength: 8)
            profileAvatarButton
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsBgGrouped)
    }

    // Avatar button → the Profile screen (account, notifications, follows).
    private var profileAvatarButton: some View {
        Button { showProfile = true } label: {
            ZStack {
                Circle().fill(Color.dsBgCard)
                Image(systemName: "person.fill")
                    .dsFont(14)
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
        let teams = viewModel.followedTeamAbbreviations(following: following)
        let result = viewModel.teamContent(following: following)
        section("From your teams") {
            // Online-only: a failed live fetch shows an honest tap-to-retry card for
            // THIS module only (the rest of Home stays usable) — never stale/seed.
            if let error = viewModel.contentError {
                moduleError(error) { await viewModel.retryContent(following: following) }
            }
            // Follow prompt only when on "All" with nothing to show (no follows / no
            // fresh content). A per-team chip coming up empty is a quiet team, not an
            // empty home — show the chips + a "No content from X" note instead.
            else if result.cards.isEmpty && viewModel.selectedTeam == nil {
                followPrompt
            } else {
                VStack(spacing: 14) {
                    // Per-team chips only when following 2+ teams — with one team
                    // there's nothing to filter (chip redesign).
                    if teams.count >= 2 {
                        HomeTeamChips(viewModel: viewModel, teams: teams)
                    }
                    if result.cards.isEmpty {
                        Text("No content from \(viewModel.selectedTeam ?? "") right now.")
                            .dsFont(13)
                            .foregroundStyle(Color.dsFgSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(result.cards) { card in
                            ContentCardView(
                                card: card,
                                club: viewModel.club(forAbbreviation: card.teamAbbreviation ?? ""),
                                // Following one team → drop the redundant team badge +
                                // name on every card (chip redesign, adaptive labels).
                                hideTeamIdentity: teams.count <= 1
                            )
                        }
                    }
                    if result.overflowCount > 0 { seeMoreLink }
                }
            }
        }
    }

    // Opens the full chronological list of all followed-team content (Change 1),
    // respecting the active chip. Appears only when the balanced module is capping
    // content off.
    private var seeMoreLink: some View {
        NavigationLink {
            HomeContentListView(viewModel: viewModel)
        } label: {
            HStack {
                Text("See more from your teams →")
                    .dsFont(13, weight: .semibold)
                    .foregroundStyle(Color.dsAccent)
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.top, 2)
        }
        .buttonStyle(.plain)
    }

    // Shown when the user follows nobody (so the lead module has nothing to show).
    private var followPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "star")
                .dsFont(32)
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
        if let error = viewModel.spotlightError {
            // Module 2 failed its live fetch — honest tap-to-retry, scoped to it.
            section(
                "Weekly Player Spotlight",
                subtitle: "A featured player each week — get to know the squad you follow"
            ) {
                moduleError(error) { await viewModel.retryContent(following: following) }
            }
        } else if !spotlights.isEmpty {
            section(
                "Weekly Player Spotlight",
                subtitle: "A featured player each week — get to know the squad you follow"
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

    // Fan Zone visibility rule: each game has its own gate, and a game with nothing
    // active/upcoming is hidden EVERYWHERE (card + screen) — no dead links or stale
    // states. The module itself hides when no game is visible (offseason). Predict
    // the XI's gate is a followed-team fixture within 28 days; Bracket and Daily
    // Trivia are seed-backed so always have content for now (their real gates land
    // when they go live).
    private var predictXIVisible: Bool { predictXIActive }
    private var bracketVisible: Bool { bracket.hasActiveEdition }
    private var triviaVisible: Bool { true }

    /// The visible games, ordered most time-sensitive first. Predict the XI is
    /// matchday-driven AND personal (you predict YOUR team's lineup), so it leads
    /// when a followed team has a fixture within 28 days; Bracket Battle and Daily
    /// Trivia follow. The first entry becomes the featured lead card.
    private enum FanGame: Hashable { case predict, bracket, trivia }
    private var visibleGames: [FanGame] {
        var games: [FanGame] = []
        if predictXIVisible { games.append(.predict) }
        if bracketVisible { games.append(.bracket) }
        if triviaVisible { games.append(.trivia) }
        return games
    }

    @ViewBuilder
    private var playSection: some View {
        let games = visibleGames
        if let featured = games.first {
            let rest = Array(games.dropFirst())
            section(
                "Fan Zone",
                subtitle: "Test your NWSL knowledge and compete with other fans",
                accessory: { activeGamesIndicator }
            ) {
                VStack(spacing: 12) {
                    // A full-width featured card anchors the section (so Fan Zone reads
                    // as prominent, not a runt) ...
                    NavigationLink { destination(for: featured) } label: {
                        featuredCard(for: featured)
                    }
                    .buttonStyle(.plain)

                    // ... then the remaining games as a scrolling row of tiles.
                    if !rest.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(rest, id: \.self) { game in
                                    NavigationLink { destination(for: game) } label: {
                                        tileCard(for: game)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 2)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func destination(for game: FanGame) -> some View {
        switch game {
        case .predict: PredictXIView()
        case .bracket: BracketBattleView()
        case .trivia:  DailyTriviaView()
        }
    }

    @ViewBuilder
    private func tileCard(for game: FanGame) -> some View {
        switch game {
        case .predict: predictGameCard
        case .bracket: bracketGameCard
        case .trivia:  triviaGameCard
        }
    }

    @ViewBuilder
    private func featuredCard(for game: FanGame) -> some View {
        switch game {
        case .predict:
            FeaturedGameCard(
                emoji: "⚽", title: "Predict the XI",
                statusLine: predict.hasPredicted ? "\(predict.seasonPoints) pts" : "Predict now",
                tagline: "Pick your team's XI before kickoff",
                accent: .dsGamePredict,
                badge: predict.seasonPoints > 0 ? "\(predict.seasonPoints)" : nil, badgeIcon: "⚽"
            )
        case .bracket:
            FeaturedGameCard(
                emoji: "🏆", title: "Bracket Battle",
                statusLine: bracketStateLine,
                tagline: "Vote the bracket, climb the leaderboard",
                accent: .dsGameBracket,
                badge: bracket.points > 0 ? "\(bracket.points)" : nil, badgeIcon: "🏆"
            )
        case .trivia:
            FeaturedGameCard(
                emoji: "🧠", title: "Daily Trivia",
                statusLine: trivia.hasPlayedToday ? "Done today ✓" : "Play now",
                tagline: "5 questions a day — keep your streak alive",
                accent: .dsGameTrivia,
                badge: trivia.streak > 0 ? "\(trivia.streak)" : nil, badgeIcon: "🔥",
                completed: trivia.hasPlayedToday
            )
        }
    }

    /// Predict the XI is active when a followed team has a fixture within the
    /// 28-day window — the gate that hides the game (card + screen) in a long
    /// break. Shares the horizon with PredictXIViewModel's slate.
    private var predictXIActive: Bool {
        let now = Date()
        let horizon = now.addingTimeInterval(PredictionFixture.activeWindow)
        return following.followedIDs.contains { id in
            guard let club = clubStore.club(id: id) else { return false }
            return matchStore.matches(for: club).contains { event in
                guard let kickoff = event.kickoff else { return false }
                return kickoff > now && kickoff <= horizon
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
                    .dsFont(11)
                    .foregroundStyle(Color.dsFgSecondary)
            }
        }
    }

    private var activeGameCount: Int {
        var n = 0
        if predictXIActive { n += 1 }                  // a followed-team fixture is up
        if bracket.hasActiveEdition { n += 1 }
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
            accent: .dsGameBracket, completed: false,
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
        guard let summary = bracket.summary, summary.isActive else { return "Play now" }
        if !bracket.hasPlayed { return "Vote now" }
        return BracketRound(rawValue: summary.currentRoundRaw)?.title ?? "In progress"
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
                .dsFont(12)
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
                        .dsFont(20, weight: .bold)
                        .foregroundStyle(Color.dsFgPrimary)
                    Spacer(minLength: 8)
                    accessory()
                }
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .dsFont(12)
                        .foregroundStyle(Color.dsFgSecondary)
                }
            }
            content()
        }
    }

    /// A compact, honest per-module failure card: the whole card is tappable to
    /// retry (so the "tap to retry" copy is literal). Used by Modules 1 & 2 so a
    /// content/spotlight fetch failure degrades that module alone — never the whole
    /// hub, and never to stale/seed content.
    private func moduleError(_ message: String, retry: @escaping () async -> Void) -> some View {
        Button { Task { await retry() } } label: {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .dsFont(22)
                    .foregroundStyle(Color.dsFgSecondary)
                Text(message)
                    .dsFont(14, weight: .medium)
                    .foregroundStyle(Color.dsFgSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .background(Color.dsBgCard)
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        // Refetch Module-1 content, reset the chip to All, and rotate the window if
        // nothing new arrived (Change 1 pull-to-refresh behavior).
        await viewModel.refresh(following: following)
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
